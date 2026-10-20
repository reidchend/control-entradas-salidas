import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Error del servicio de IA con un mensaje ya listo para mostrar al usuario.
class IaException implements Exception {
  const IaException(this.mensaje, {this.herramientaNoSoportada = false});

  final String mensaje;

  /// `true` cuando el error fue porque el modelo no acepta la herramienta de
  /// búsqueda: el llamador reintenta sin ella.
  final bool herramientaNoSoportada;

  @override
  String toString() => mensaje;
}

/// Cliente mínimo de Gemini para analizar una imagen.
///
/// Usa la API REST (`generateContent`) con la herramienta de búsqueda de
/// Google: el modelo mira la foto, busca marca/modelo en la web y devuelve un
/// texto (se le pide JSON). No se agrega SDK: `http` ya está en el proyecto.
class GeminiVision {
  GeminiVision({http.Client? cliente})
      : _cliente = cliente ?? http.Client(),
        _propio = cliente == null;

  final http.Client _cliente;
  final bool _propio;

  /// Libera el cliente HTTP si lo creó este objeto.
  void cerrar() {
    if (_propio) _cliente.close();
  }

  static const _base =
      'https://generativelanguage.googleapis.com/v1beta/models';
  static const _espera = Duration(seconds: 60);

  /// Analiza [imagen] con [prompt] y devuelve el texto que responde el modelo.
  Future<String> analizarImagen({
    required String apiKey,
    required String modelo,
    required String prompt,
    required Uint8List imagen,
    String mime = 'image/jpeg',
  }) async {
    final uri = Uri.parse(
      '$_base/${Uri.encodeComponent(modelo)}:generateContent',
    );
    final partes = <Map<String, dynamic>>[
      {'text': prompt},
      {
        'inline_data': {
          'mime_type': mime,
          'data': base64Encode(imagen),
        },
      },
    ];

    // Primero con búsqueda web; si el modelo no la soporta, se reintenta sin
    // ella: mejor una identificación sin internet que un error seco.
    try {
      return await _pedir(uri, apiKey, partes, conBusqueda: true);
    } on IaException catch (e) {
      if (!e.herramientaNoSoportada) rethrow;
      return _pedir(uri, apiKey, partes, conBusqueda: false);
    }
  }

  Future<String> _pedir(
    Uri uri,
    String apiKey,
    List<Map<String, dynamic>> partes, {
    required bool conBusqueda,
  }) async {
    http.Response respuesta;
    try {
      respuesta = await _cliente
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': partes,
                },
              ],
              if (conBusqueda) 'tools': [
                {'google_search': <String, dynamic>{}},
              ],
              'generationConfig': {
                'temperature': 0.2,
                // Holgado a propósito: en los modelos con "thinking" los
                // tokens de razonamiento también consumen este tope.
                'maxOutputTokens': 3000,
              },
            }),
          )
          .timeout(_espera);
    } on TimeoutException {
      throw const IaException(
        'La identificación tardó demasiado. Revisá la conexión y reintentá.',
      );
    } catch (_) {
      throw const IaException(
        'No se pudo conectar con el servicio de IA. '
        'Revisá la conexión a internet e intentá de nuevo.',
      );
    }

    if (respuesta.statusCode != 200) {
      throw _errorHttp(respuesta, conBusqueda: conBusqueda);
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(respuesta.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      throw const IaException(
        'El servicio de IA devolvió una respuesta ilegible.',
      );
    }

    final feedback = data['promptFeedback'] as Map<String, dynamic>?;
    final bloqueo = feedback?['blockReason'];
    if (bloqueo != null) {
      throw IaException(
        'La imagen fue bloqueada por el filtro de seguridad de Gemini '
        '($bloqueo). Probá con otra foto.',
      );
    }

    final candidatos = (data['candidates'] as List?) ?? const [];
    if (candidatos.isEmpty) {
      throw const IaException(
        'El servicio de IA no devolvió respuesta. Probá con otra foto.',
      );
    }
    final contenido = (candidatos.first as Map)['content'] as Map?;
    final partesRespuesta = (contenido?['parts'] as List?) ?? const [];
    final texto = partesRespuesta
        .whereType<Map>()
        .where((p) => p['thought'] != true)
        .map((p) => '${p['text'] ?? ''}')
        .join()
        .trim();

    if (texto.isEmpty) {
      throw const IaException(
        'El servicio de IA no devolvió texto. Probá con otra foto.',
      );
    }
    return texto;
  }

  IaException _errorHttp(http.Response r, {required bool conBusqueda}) {
    final detalle = _detalleDe(r.body);
    final minuscula = detalle.toLowerCase();
    final sinHerramienta = conBusqueda &&
        r.statusCode == 400 &&
        (minuscula.contains('search') || minuscula.contains('tool'));
    switch (r.statusCode) {
      case 400:
        return IaException(
          'La solicitud a Gemini no es válida. '
          'Revisá el modelo configurado en Ajustes → IA.'
          '${detalle.isEmpty ? '' : '\n\n$detalle'}',
          herramientaNoSoportada: sinHerramienta,
        );
      case 401:
      case 403:
        return const IaException(
          'La clave de Gemini no es válida o no tiene permisos. '
          'Cambiala en Ajustes → IA.',
        );
      case 404:
        return const IaException(
          'El modelo de IA configurado no existe para esta clave. '
          'Revisá el modelo en Ajustes → IA.',
        );
      case 429:
        return const IaException(
          'Se agotó la cuota de Gemini por ahora. '
          'Esperá unos minutos y reintentá.',
        );
      default:
        return IaException(
          'Gemini devolvió un error (${r.statusCode}).'
          '${detalle.isEmpty ? '' : ' $detalle'}',
        );
    }
  }

  /// Mensaje corto del JSON de error de Google, sin el volcado completo.
  String _detalleDe(String cuerpo) {
    try {
      final data = jsonDecode(cuerpo) as Map<String, dynamic>;
      final error = data['error'] as Map<String, dynamic>?;
      final mensaje = (error?['message'] as String?)?.trim() ?? '';
      if (mensaje.length > 200) return '${mensaje.substring(0, 200)}…';
      return mensaje;
    } catch (_) {
      return '';
    }
  }
}
