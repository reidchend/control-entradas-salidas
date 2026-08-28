import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../../core/data/supabase_service.dart';
import '../../../core/models/mensaje_whatsapp.dart';

const whatsappBotToken = 'mi_token_secreto_123';
const String _fallbackBotUrl = 'https://lycoris-bot.shares.zrok.io';
const String _gistRawUrl = 'https://gist.githubusercontent.com/reidchend/5b37693a243d8d2235eea0647396b8d3/raw/bot_url.json';

class WhatsappRepository {
  WhatsappRepository(this._db);
  final SupabaseService _db;

  String? _cachedBotUrl;

  Future<String> get botUrl async {
    if (_cachedBotUrl != null) return _cachedBotUrl!;

    try {
      final resp = await http.get(Uri.parse(_gistRawUrl))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data.containsKey('url')) {
          _cachedBotUrl = data['url'] as String;
          return _cachedBotUrl!;
        }
      }
    } catch (_) {}

    _cachedBotUrl = _fallbackBotUrl;
    return _cachedBotUrl!;
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
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map(MensajeWhatsapp.fromMap).toList();
  }

  Future<int> countPending() async {
    final rows = await _db.client
        .from('whatsapp_queue')
        .select('id')
        .eq('estado', 'pending')
        .lt('intentos', 5);
    return rows.length;
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

  Future<int> reintentarTodos({int limit = 20}) async {
    final pendientes = await getMensajesEstados(
      estados: const ['pending', 'failed'],
      limit: limit,
    );
    var ok = 0;
    for (final msg in pendientes) {
      if (await _enviarDesdeCola(msg)) ok++;
    }
    return ok;
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

  Future<bool> _enviarDesdeCola(MensajeWhatsapp msg) async {
    if (msg.estado != 'pending' && msg.estado != 'failed') return false;
    await updateEstado(msg.id, 'sending');
    final success = msg.tipo == 'image'
        ? await _enviarImagenDirecto(
            imagenBase64: msg.imagenBase64 != null
                ? _ensureJpegBase64(msg.imagenBase64!)
                : null,
            caption: msg.mensaje ?? '')
        : await _enviarTextoDirecto(msg.mensaje ?? '');
    if (success) {
      await updateEstado(msg.id, 'sent');
    } else {
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
        .limit(limit);
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
