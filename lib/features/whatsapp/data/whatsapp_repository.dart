import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../../core/data/postgres_service.dart';
import '../../../core/models/mensaje_whatsapp.dart';

/// Token del bot para `x-auth-token`. Se inyecta en el build con
/// `--dart-define=WHATSAPP_BOT_TOKEN=<token>` (ver docs/montar-pc-servidor.md).
/// Sin define queda vacío: el bot rechaza el envío, el mensaje se encola y
/// se reintenta; el binario nunca lleva el secreto del repo.
const whatsappBotToken = String.fromEnvironment('WHATSAPP_BOT_TOKEN');
const String _gistRawUrl = 'https://gist.githubusercontent.com/reidchend/5b37693a243d8d2235eea0647396b8d3/raw/bot_url.json';

class WhatsappRepository {
  WhatsappRepository(this._db);
  final PostgresService _db;

  String? _cachedBotUrl;
  Timer? _retryTimer;

  /// Inicia el timer de reintentos cada 1 minuto (hasta 5 intentos por mensaje).
  void startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      reintentarTodos(limit: 20).catchError((e) {
        print('[WA] retry timer error: $e');
        return 0;
      });
    });
  }

  /// Detiene el timer de reintentos.
  void stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<String> get botUrl async {
    if (_cachedBotUrl != null) return _cachedBotUrl!;

    try {
      final resp = await http.get(Uri.parse(_gistRawUrl))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final raw = data is Map ? data['url'] : null;
        if (raw is String && raw.isNotEmpty) {
          _cachedBotUrl = raw;
          return raw;
        }
      }
    } catch (_) {}

    // Sin URL válida en cache: devolver cadena vacía SIN cachearla, para que
    // el próximo reenvío vuelva al Gist (el túnel puede haber cambiado de URL
    // mientras tanto). El envío va al fallo y se encola.
    return '';
  }

  void invalidateCache() {
    _cachedBotUrl = null;
  }

  Future<List<MensajeWhatsapp>> getMensajes({
    String? estado,
    int limit = 100,
  }) async {
    var query = _db.client.from('whatsapp_queue').select();
    if (estado != null) query = query.eq('estado', estado);
    final rows = await query.order('created_at', ascending: false).limit(limit)
        as List<Map<String, dynamic>>;
    return rows.map(MensajeWhatsapp.fromMap).toList();
  }

  Future<int> countPending() async {
    // COUNT(*) en BD en vez de traer todos los ids para contarlos en Dart.
    final rows = await _db.executeSql(
      'SELECT COUNT(*) AS n FROM whatsapp_queue WHERE estado = \$1 AND intentos < \$2',
      params: ['pending', 5],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  Future<void> saveToQueue({
    required String tipo,
    String mensaje = '',
    String? imagenBase64,
    String? imagenPath,
  }) async {
    final now = DateTime.now().toIso8601String();
    await _db.insert('whatsapp_queue', {
      'tipo': tipo,
      'mensaje': mensaje,
      'imagen_base64': imagenBase64,
      'imagen_path': imagenPath,
      'estado': 'pending',
      'intentos': 0,
      'max_intentos': 5,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateEstado(int id, String estado, {String? error}) async {
    await _db.updateById('whatsapp_queue', id, {
      'estado': estado,
      if (error != null) 'ultimo_error': error,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> eliminar(int id) async {
    await _db.deleteById('whatsapp_queue', id);
  }

  Map<String, String> get _headers => {
        'x-auth-token': whatsappBotToken,
      };

  /// Convierte bytes de imagen a JPEG base64 si es necesario.
  /// El clipboard de Windows devuelve BMP/DIB que WhatsApp no puede mostrar.
  static String _ensureJpegBase64(String base64Image) {
    try {
      final bytes = base64Decode(base64Image);

      // JPEG: FF D8 FF
      if (bytes.length >= 3 &&
          bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return base64Image;
      }
      // PNG: 89 50 4E 47
      if (bytes.length >= 4 &&
          bytes[0] == 0x89 && bytes[1] == 0x50 &&
          bytes[2] == 0x4E && bytes[3] == 0x47) {
        return base64Image;
      }

      // Otro formato (BMP, TIFF, etc.) → decodificar y re-encodear como JPEG
      final image = img.decodeImage(bytes);
      if (image == null) return base64Image;
      final jpeg = img.encodeJpg(image, quality: 85);
      return base64Encode(jpeg);
    } catch (_) {
      return base64Image;
    }
  }

  Future<bool> _enviarTextoDirecto(String mensaje) async {
    try {
      final url = await botUrl;
      final resp = await http
          .post(
            Uri.parse('$url/send'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'message': mensaje}),
          )
          .timeout(const Duration(seconds: 30));
      return resp.statusCode == 200;
    } catch (e) {
      print('[WA] send texto error: $e');
      return false;
    }
  }

  Future<bool> _enviarImagenDirecto({
    String? imagenBase64,
    String caption = '',
  }) async {
    final b64 = imagenBase64;
    if (b64 == null || b64.isEmpty) return false;
    try {
      final url = await botUrl;
      final resp = await http
          .post(
            Uri.parse('$url/send-image'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'imageBase64': b64, 'caption': caption}),
          )
          .timeout(const Duration(seconds: 30));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<({bool connected, String? groupId, String? reportGroupId})> getStatus() async {
    try {
      final url = await botUrl;
      final resp = await http
          .get(Uri.parse('$url/config'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        return (connected: false, groupId: null, reportGroupId: null);
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (
        connected: data['whatsapp_connected'] == true,
        groupId: data['group_id'] as String?,
        reportGroupId: data['report_group_id'] as String?,
      );
    } catch (_) {
      return (connected: false, groupId: null, reportGroupId: null);
    }
  }

  Future<bool> _enviarReporteDirecto(String mensaje) async {
    try {
      final url = await botUrl;
      final resp = await http
          .post(
            Uri.parse('$url/send-report'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'message': mensaje}),
          )
          .timeout(const Duration(seconds: 30));
      return resp.statusCode == 200;
    } catch (e) {
      print('[WA] send report error: $e');
      return false;
    }
  }

  Future<bool> _enviarDocumentoDirecto({
    required String fileName,
    required String content,
    String caption = '',
  }) async {
    try {
      final url = await botUrl;
      final resp = await http
          .post(
            Uri.parse('$url/send-document'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'fileName': fileName,
              'content': content,
              'caption': caption,
            }),
          )
          .timeout(const Duration(seconds: 30));
      return resp.statusCode == 200;
    } catch (e) {
      print('[WA] send document error: $e');
      return false;
    }
  }

  /// Envía el reporte simple (texto) al grupo de reportes.
  Future<bool> enviarReporteSimple(String mensaje) async {
    if (await _enviarReporteDirecto(mensaje)) return true;
    await saveToQueue(tipo: 'report_simple', mensaje: mensaje);
    return false;
  }

  /// Envía el reporte detallado (.txt) al grupo de reportes.
  Future<bool> enviarReporteDetallado({
    required String fileName,
    required String content,
    String caption = '',
  }) async {
    if (await _enviarDocumentoDirecto(fileName: fileName, content: content, caption: caption)) {
      return true;
    }
    await saveToQueue(
      tipo: 'report_detail',
      mensaje: caption,
      imagenBase64: base64Encode(utf8.encode(content)), // guardamos el contenido en base64
      imagenPath: fileName,
    );
    return false;
  }

  Future<bool> enviarMensaje(String mensaje) async {
    if (await _enviarTextoDirecto(mensaje)) return true;
    await saveToQueue(tipo: 'text', mensaje: mensaje);
    return false;
  }

  Future<bool> enviarImagen({
    required String? imagenBase64,
    String caption = '',
  }) async {
    if (imagenBase64 != null && imagenBase64.isNotEmpty) {
      final jpeg = _ensureJpegBase64(imagenBase64);
      if (await _enviarImagenDirecto(imagenBase64: jpeg, caption: caption)) {
        return true;
      }
    }
    await saveToQueue(
      tipo: imagenBase64 != null ? 'image' : 'text',
      mensaje: caption,
      imagenBase64: imagenBase64,
    );
    return false;
  }

  bool _reintentando = false;

  Future<int> reintentarTodos({int limit = 20}) async {
    // Guarda de vuelo: si una corrida tarda más que el intervalo del timer, no
    // iniciar otra en paralelo (evita envíos duplicados).
    if (_reintentando) return 0;
    _reintentando = true;
    try {
      final pendientes = await getMensajesEstados(
        estados: const ['pending', 'failed'],
        limit: limit,
      );
      var ok = 0;
      final exitosos = <int>[];
      for (final msg in pendientes) {
        if (await _enviarDesdeCola(msg, registrarLogro: false)) {
          ok++;
          exitosos.add(msg.id);
        }
      }
      // Marcar los exitosos en una sola escritura.
      if (exitosos.isNotEmpty) {
        await _db.executeSql(
          'UPDATE whatsapp_queue SET estado = \$1, updated_at = \$2 '
          'WHERE id = ANY(\$3)',
          params: ['sent', DateTime.now().toIso8601String(), exitosos],
        );
      }
      return ok;
    } finally {
      _reintentando = false;
    }
  }

  Future<bool> reintentarUno(int id) async {
    final rows = await _db.client
        .from('whatsapp_queue')
        .select()
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return false;
    return _enviarDesdeCola(MensajeWhatsapp.fromMap(rows.first));
  }

  Future<bool> _enviarDesdeCola(MensajeWhatsapp msg,
      {bool registrarLogro = true}) async {
    if (msg.estado != 'pending' && msg.estado != 'failed') return false;
    await updateEstado(msg.id, 'sending');
    // Cada tipo va a su endpoint/grupo correcto:
    // - image → foto (grupo principal)
    // - report_simple / report_detail → grupo de reportes/cierres
    // - resto → texto del grupo principal
    final bool success;
    switch (msg.tipo) {
      case 'image':
        success = await _enviarImagenDirecto(
          imagenBase64: msg.imagenBase64 != null
              ? _ensureJpegBase64(msg.imagenBase64!)
              : null,
          caption: msg.mensaje ?? '',
        );
      case 'report_simple':
        success = await _enviarReporteDirecto(msg.mensaje ?? '');
      case 'report_detail':
        String content = '';
        final b64 = msg.imagenBase64;
        if (b64 != null && b64.isNotEmpty) {
          try {
            content = utf8.decode(base64Decode(b64));
          } catch (_) {}
        }
        success = await _enviarDocumentoDirecto(
          fileName: msg.imagenPath ?? 'reporte.txt',
          content: content,
          caption: msg.mensaje ?? '',
        );
      default:
        success = await _enviarTextoDirecto(msg.mensaje ?? '');
    }
    if (success) {
      // En `reintentarTodos` el logro se registra en lote al final.
      if (registrarLogro) await updateEstado(msg.id, 'sent');
    } else {
      // El fallo puede ser por URL obsoleta (túnel reiniciado): descartar la
      // caché para que el próximo reintento vuelva a leer el Gist.
      invalidateCache();
      final intentos = msg.intentos + 1;
      final estado = intentos >= msg.maxIntentos ? 'failed' : 'pending';
      await _db.updateById('whatsapp_queue', msg.id, {
        'intentos': intentos,
        'estado': estado,
        'ultimo_error': 'Error de conexion',
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
    return success;
  }

  Future<List<MensajeWhatsapp>> getMensajesEstados({
    required List<String> estados,
    int limit = 50,
  }) async {
    final rows = await _db.client
        .from('whatsapp_queue')
        .select()
        .filter('estado', 'in', estados)
        .order('created_at', ascending: true)
        .limit(limit) as List<Map<String, dynamic>>;
    return rows.map(MensajeWhatsapp.fromMap).toList();
  }

  Future<bool> probarBot(String usuario) async {
    final ts = _fmtFechaHora(DateTime.now());
    final msg = '*Bot activo*\nUsuario: $usuario\nHora: $ts';
    return enviarMensaje(msg);
  }
}

String _fmtFechaHora(DateTime d) {
  String p(int v) => v.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}';
}

String formatValidationMessage({
  required String productos,
  required String proveedor,
  required String factura,
  double monto = 0,
  String usuario = '',
  DateTime? fechaEntrada,
}) {
  final fechaStr = fechaEntrada != null
      ? _fmtFechaHora(fechaEntrada)
      : _fmtFechaHora(DateTime.now());
  final productosBlock = productos.contains('\n')
      ? '📦 *Cargo productos:*\n'
          '${productos.split('\n').map((l) => '• $l').join('\n')}'
      : '📦 *Cargo productos:* $productos';
  return '✅ *ENTRADA VALIDADA*\n\n'
      '$productosBlock\n'
      '🏪 *Proveedor:* $proveedor\n'
      '🧾 *Factura:* $factura\n'
      '📅 *Fecha:* $fechaStr\n'
      '👤 *Usuario:* $usuario\n\n'
      '_Lycoris bot_';
}
