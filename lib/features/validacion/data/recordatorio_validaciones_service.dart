import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/data/postgres_service.dart';
import '../../whatsapp/data/whatsapp_repository.dart';
import 'validacion_repository.dart';

/// Envía recordatorios al grupo de WhatsApp con las compras (entradas) que
/// siguen sin validar, incluyendo el motivo de cada una.
///
/// Dos disparadores, elegidos para que avisar no se vuelva invasivo:
///
/// 1. **Tanda nueva**: cuando aparece una entrada nueva en la lista de
///    validación se espera [debounce] (30 min) por si esa tanda trae más
///    compras, y recién ahí se envía el recordatorio con TODO lo pendiente.
///    No dispara por cada entrada: una notificación por tanda.
/// 2. **Cierre del día**: a las 19:00 se reenvía mientras queden pendientes
///    (una vez por día), para que nada se quede durmiendo.
///
/// Si no hay pendientes no se envía nada. Cada aviso queda marcado en
/// `pos_settings` para que dos equipos con la app abierta no dupliquen el
/// mensaje en el grupo, y si el bot está caído el mensaje cae en
/// `whatsapp_queue` y se reintenta solo (lo hace `WhatsappRepository`).
class RecordatorioValidacionesService {
  RecordatorioValidacionesService(PostgresService db, WhatsappRepository wa)
      : _db = db,
        _wa = wa,
        _validaciones = ValidacionRepository(db);

  final PostgresService _db;
  final WhatsappRepository _wa;
  final ValidacionRepository _validaciones;

  /// Espera tras la primera entrada nueva de una tanda antes de avisar.
  static const Duration debounce = Duration(minutes: 30);

  /// Frecuencia con la que se mira la lista (las entradas pueden registrarse
  /// en otro equipo con la app abierta).
  static const Duration _intervaloPoll = Duration(minutes: 2);

  /// Hora del aviso fijo de cierre (19:00).
  static const int _horaAvisoFijo = 19;

  /// Ventana en la que un aviso de tanda se considera duplicado (otro equipo
  /// recién lo envió).
  static const Duration _guardDuplicados = Duration(minutes: 25);

  /// `pos_settings.key` del switch de encendido/apagado (Sistema).
  static const String kSettingEnabled = 'recordatorio_validaciones';
  static const String _kUltimoTs = 'recordatorio_validaciones_ultimo_ts';
  static const String _kFijoFecha = 'recordatorio_validaciones_fijo_fecha';

  Timer? _pollTimer;
  Timer? _debounceTimer;

  /// Id mayor de entrada pendiente ya conocido. `null` hasta el primer poll.
  int? _maxIdVisto;
  bool _enviando = false;

  void iniciar() {
    detener();
    _pollTimer = Timer.periodic(_intervaloPoll, (_) => _poll());
    // Primera revisión inmediata: solo anota el estado actual (ver _poll),
    // para no avisar por entradas que ya existían antes de abrir la app.
    _poll();
  }

  void detener() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  Future<void> _poll() async {
    try {
      final valor = (await _getSetting(kSettingEnabled))?.toLowerCase();
      if (valor == '0' || valor == 'false' || valor == 'off') {
        // Apagado desde Configuración: sin avisos ni esperas pendientes.
        _debounceTimer?.cancel();
        _debounceTimer = null;
        return;
      }

      // Consulta liviana: cuántas pendientes hay y cuál es la más nueva.
      final rows = await _db.executeSql(
        "SELECT COUNT(*) AS n, COALESCE(MAX(id), 0) AS max_id "
        "FROM movimientos WHERE tipo = 'entrada' AND factura_id IS NULL",
      );
      if (rows.isEmpty) return;
      final n = (rows.first['n'] as num?)?.toInt() ?? 0;
      final maxId = (rows.first['max_id'] as num?)?.toInt() ?? 0;

      final visto = _maxIdVisto;
      if (visto == null) {
        // Primer poll tras arrancar: se anota el estado actual y no se
        // dispara nada por lo que ya estaba pendiente.
        _maxIdVisto = maxId;
        return;
      }

      // Aviso fijo de cierre: una vez por día, solo si hay pendientes.
      final ahora = DateTime.now();
      final fechaHoy =
          '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-'
          '${ahora.day.toString().padLeft(2, '0')}';
      if (n > 0 &&
          ahora.hour >= _horaAvisoFijo &&
          await _getSetting(_kFijoFecha) != fechaHoy) {
        final ultimo = DateTime.tryParse(
            (await _getSetting(_kUltimoTs)).toString());
        final huboAvisoReciente = ultimo != null &&
            DateTime.now().difference(ultimo) < _guardDuplicados;
        if (huboAvisoReciente) {
          // Otra tanda (de este u otro equipo) acaba de avisar de lo mismo:
          // el fijo de hoy queda cubierto y no se duplica el mensaje.
          await _setSetting(_kFijoFecha, fechaHoy);
        } else if (await _enviar(esFijo: true)) {
          await _setSetting(_kFijoFecha, fechaHoy);
        }
      }

      // Entrada nueva → esperar la tanda y avisar una sola vez.
      if (maxId > visto && _debounceTimer == null) {
        _debounceTimer = Timer(debounce, () {
          _debounceTimer = null;
          _enviar(esFijo: false);
        });
      }
      // Se anota aunque haya debounce en curso: las entradas que lleguen
      // durante la espera se incluyen en el mensaje (se arma al enviar).
      _maxIdVisto = maxId;
    } catch (e) {
      debugPrint('[recordatorio] poll error: $e');
    }
  }

  /// Envía el recordatorio con todo lo pendiente. Marca el envío en
  /// `pos_settings` para que otro equipo no lo duplique; si el envío directo
  /// al bot falla, el mensaje queda encolado y también se marca (el
  /// reintento lo hace la bandeja de WhatsApp).
  Future<bool> _enviar({required bool esFijo}) async {
    if (_enviando) return false;
    _enviando = true;
    try {
      final pendientes = await _validaciones.getEntradasPendientes();
      if (pendientes.isEmpty) return false; // validadas durante la espera

      // Guard multi-dispositivo para las tandas: si otro equipo acaba de
      // mandar el mismo aviso, no duplicar el mensaje en el grupo.
      if (!esFijo) {
        final ultimo = DateTime.tryParse(
            (await _getSetting(_kUltimoTs)).toString());
        if (ultimo != null &&
            DateTime.now().difference(ultimo) < _guardDuplicados) {
          return false;
        }
      }

      final directo = await _wa.enviarMensaje(_armarMensaje(pendientes,
          esFijo: esFijo));
      // true = enviado; false = encolado (el bot estaba caído). En ambos
      // casos el mensaje quedó encaminado y el aviso se marca.
      await _setSetting(
          _kUltimoTs, DateTime.now().toIso8601String());
      debugPrint('[recordatorio] avisado (${pendientes.length} pendientes, '
          'fijo=$esFijo, directo=$directo)');
      return true;
    } catch (e) {
      debugPrint('[recordatorio] envio error: $e');
      return false;
    } finally {
      _enviando = false;
    }
  }

  String _armarMensaje(List<EntradaPendiente> pendientes,
      {required bool esFijo}) {
    final detalle = [
      for (final e in pendientes)
        '• ${e.nombre}: ${e.cantidadTexto}'
        ' — ${(e.motivoNoValidacion ?? '').trim().isNotEmpty ? e.motivoNoValidacion!.trim() : 'sin motivo anotado'}',
    ].join('\n');
    return '⏰ *HAY COMPRAS SIN VALIDAR* '
        '(${pendientes.length})\n\n'
        'Esperan validación:\n$detalle\n\n'
        '${esFijo ? 'Recordatorio del cierre del día (19:00).'
                  : 'Nueva compra registrada hace 30 min.'}\n\n'
        '_Lycoris bot_';
  }

  // -------------------------------------------------------------------------
  // pos_settings (mismo patrón que ConfiguracionRepository)
  // -------------------------------------------------------------------------

  Future<String?> _getSetting(String key) async {
    try {
      final row = await _db.fetchByField('pos_settings', 'key', key);
      return (row?['value'] as String?)?.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _setSetting(String key, String value) async {
    try {
      // pos_settings no tiene columna `id` (la PK es `key`), así que el
      // upsert genérico (que hace RETURNING id) no sirve: ON CONFLICT puro.
      await _db.executeSql(
        'INSERT INTO pos_settings (key, value) VALUES (\$1, \$2) '
        'ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value',
        params: [key, value],
      );
    } catch (e) {
      debugPrint('[recordatorio] no se pudo guardar $key: $e');
    }
  }
}
