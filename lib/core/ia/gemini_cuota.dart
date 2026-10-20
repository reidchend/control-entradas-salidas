import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Uso de la cuota de Gemini en el día de Google, por modelo.
///
/// Google **no** publica cuántos intentos le quedan a una clave: solo dice el
/// límite total cuando se acaba, y ese límite lo aprendemos del error 429. Para
/// poder mostrar "37 de 250 usadas hoy", la app cuenta sus propias
/// identificaciones por modelo.
///
/// Lo que cuenta es **este dispositivo**: si la misma clave se usa desde otra
/// app, otro equipo o AI Studio, ese gasto no aparece acá. Por eso el número se
/// muestra siempre a la baja conservadora: nunca promete intentos que no hay.
///
/// El día no es el local: los cupos por día (RPD) se reinician a medianoche
/// **hora Pacífico**, así que el contador se agrupa por ese día.
class GeminiCuota {
  GeminiCuota._(this._prefs) : _uso = _leerUso(_prefs);

  final SharedPreferences _prefs;

  /// Conteo en memoria del día de Google vigente.
  _UsoDelDia _uso;

  static const _kUso = 'ia_cuota_uso';
  static const _kLimite = 'ia_cuota_limites';
  static const _kUltimo = 'ia_cuota_ultimo_modelo';

  static Future<GeminiCuota> abrir() async =>
      GeminiCuota._(await SharedPreferences.getInstance());

  // ---------------------------------------------------------------------
  // Registro
  // ---------------------------------------------------------------------

  /// Suma un intento de [modelo] y recuerda cuál fue el último.
  ///
  /// Es un contador de muestra, no un dato operativo: si el guardado falla se
  /// sigue contando en memoria y la identificación no se ve afectada.
  Future<void> registrarUso(String modelo) async {
    final hoy = diaDeGoogle(DateTime.now());
    if (_uso.dia != hoy) _uso = _UsoDelDia(hoy, <String, int>{});
    _uso.porModelo[modelo] = (_uso.porModelo[modelo] ?? 0) + 1;
    await _guardar(_kUso, jsonEncode(_uso.toMap()));
    await _guardar(_kUltimo, modelo);
  }

  /// Guarda el límite que Google reportó para [modelo] en un 429.
  ///
  /// El límite varía por modelo, tier y proyecto, así que no se hardcodea: se
  /// toma del error real y queda guardado hasta que cambie.
  Future<void> registrarLimite(String modelo, int limite) async {
    if (limite <= 0) return;
    final actuales = _limites();
    if (actuales[modelo] == limite) return;
    actuales[modelo] = limite;
    await _guardar(_kLimite, jsonEncode(actuales));
  }

  /// Escritura best-effort: un fallo del almacenamiento no puede cortar el
  /// resto de la operación que estaba ocurriendo.
  Future<void> _guardar(String clave, String valor) async {
    try {
      await _prefs.setString(clave, valor);
    } catch (_) {
      // Sin persistencia el contador sigue en memoria hasta cerrar la app.
    }
  }

  // ---------------------------------------------------------------------
  // Lectura
  // ---------------------------------------------------------------------

  /// Intentos usados por [modelo] en el día de Google vigente.
  int usadas(String modelo) => _uso.porModelo[modelo] ?? 0;

  /// Límite conocido de [modelo], si Google ya lo reportó en algún 429.
  int? limite(String modelo) {
    final v = _limites()[modelo];
    return (v == null || v <= 0) ? null : v;
  }

  /// Avance 0..1 de [modelo], o `null` si todavía no se conoce el límite.
  double? avance(String modelo) {
    final l = limite(modelo);
    if (l == null) return null;
    return (usadas(modelo) / l).clamp(0.0, 1.0);
  }

  /// Modelos usados hoy, del más usado al menos.
  List<String> modelosUsados() {
    final lista = _uso.porModelo.keys.toList()
      ..sort((a, b) => _uso.porModelo[b]!.compareTo(_uso.porModelo[a]!));
    return lista;
  }

  /// Último modelo con el que se identificó algo (ayer o hoy).
  String? ultimoModelo() {
    final String? valor;
    try {
      valor = _prefs.getString(_kUltimo);
    } catch (_) {
      return null;
    }
    final v = valor?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Instante en que Google reinicia el cupo diario (medianoche PT), ya
  /// convertido a la hora local del dispositivo.
  DateTime proximoReinicio() {
    final ahora = DateTime.now().toUtc();
    final offset = _esVeranoNorte(ahora) ? 7 : 8;
    final pt = ahora.subtract(Duration(hours: offset));
    final medianocheUtc = DateTime.utc(pt.year, pt.month, pt.day + 1);
    return medianocheUtc.add(Duration(hours: offset)).toLocal();
  }

  /// Día de Google (hora Pacífico) al que pertenece [ahora].
  ///
  /// Se expone para poder probarlo sin depender del reloj de la máquina.
  static String diaDeGoogle(DateTime ahora) {
    final utc = ahora.toUtc();
    final pt = utc.subtract(Duration(hours: _esVeranoNorte(utc) ? 7 : 8));
    String dd(int v) => v.toString().padLeft(2, '0');
    return '${pt.year}-${dd(pt.month)}-${dd(pt.day)}';
  }

  // ---------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------

  Map<String, int> _limites() {
    final String? raw;
    try {
      raw = _prefs.getString(_kLimite);
    } catch (_) {
      return <String, int>{};
    }
    if (raw == null) return <String, int>{};
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return <String, int>{};
      return {
        for (final e in data.entries)
          e.key: (e.value as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return <String, int>{};
    }
  }

  static _UsoDelDia _leerUso(SharedPreferences prefs) {
    final hoy = diaDeGoogle(DateTime.now());
    final String? raw;
    try {
      raw = prefs.getString(_kUso);
    } catch (_) {
      return _UsoDelDia(hoy, <String, int>{});
    }
    if (raw != null) {
      try {
        final data = jsonDecode(raw);
        if (data is Map<String, dynamic> && data['dia'] == hoy) {
          final porModelo = data['porModelo'];
          return _UsoDelDia(hoy, {
            if (porModelo is Map)
              for (final e in porModelo.entries)
                '${e.key}': (e.value as num?)?.toInt() ?? 0,
          });
        }
      } catch (_) {
        // Cache ilegible: se empieza de cero, no rompe la identificación.
      }
    }
    return _UsoDelDia(hoy, <String, int>{});
  }

  /// Horario de verano del hemisferio norte (2º domingo de marzo al 1º de
  /// noviembre), que es el que Google sigue para los cupos diarios.
  static bool _esVeranoNorte(DateTime utc) {
    final y = utc.year;
    final inicio = _segundoDomingo(y, 3);
    final fin = _primerDomingo(y, 11);
    final m = DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
    return m.isAfter(inicio) && m.isBefore(fin);
  }

  static DateTime _primerDomingo(int anio, int mes) {
    final primero = DateTime.utc(anio, mes, 1);
    return primero.add(Duration(days: (7 - primero.weekday) % 7));
  }

  static DateTime _segundoDomingo(int anio, int mes) =>
      _primerDomingo(anio, mes).add(const Duration(days: 7));
}

class _UsoDelDia {
  _UsoDelDia(this.dia, this.porModelo);

  final String dia;
  final Map<String, int> porModelo;

  Map<String, dynamic> toMap() => {'dia': dia, 'porModelo': porModelo};
}
