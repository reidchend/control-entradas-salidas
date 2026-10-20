import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Error del servicio de IA con un mensaje ya listo para mostrar al usuario.
class IaException implements Exception {
  const IaException(
    this.mensaje, {
    this.herramientaNoSoportada = false,
    this.modeloNoDisponible = false,
    this.modeloSaturado = false,
  });

  final String mensaje;

  /// `true` cuando el error fue porque el modelo no acepta la herramienta de
  /// búsqueda: el llamador reintenta sin ella.
  final bool herramientaNoSoportada;

  /// `true` cuando el modelo configurado ya no existe para esta cuenta (por
  /// ejemplo, los 2.5 en proyectos nuevos): el llamador prueba el respaldo.
  final bool modeloNoDisponible;

  /// `true` cuando Google devolvió 503 por saturación: el llamador prueba otro
  /// modelo antes de rendirse.
  final bool modeloSaturado;

  @override
  String toString() => mensaje;
}

/// Cliente mínimo de Gemini para analizar una imagen.
///
/// Usa la API REST (`generateContent`) con la herramienta de búsqueda de
/// Google cuando el plan la incluye: el modelo mira la foto, busca
/// marca/modelo en la web y devuelve un texto (se le pide JSON). Si la
/// búsqueda no está disponible, reintenta sin ella. No se agrega SDK: `http`
/// ya está en el proyecto.
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

  /// Cadena de modelos a probar si el configurado no existe para la cuenta o
  /// Google lo tiene saturado.
  ///
  /// Google cerró los 2.5 para proyectos nuevos y recomienda 3.8 Flash. Si ese
  /// devuelve 503, Flash-Lite suele tener más disponibilidad y tarda lo mismo.
  static const _respaldo = [
    'gemini-3.8-flash',
    'gemini-3.5-flash-lite',
  ];

  static const _base =
      'https://generativelanguage.googleapis.com/v1beta/models';
  static const _espera = Duration(seconds: 90);

  /// Analiza [imagen] con [prompt] y devuelve el texto que responde el modelo.
  Future<String> analizarImagen({
    required String apiKey,
    required String modelo,
    required String prompt,
    required Uint8List imagen,
    String mime = 'image/jpeg',
  }) async {
    final modelos = <String>[modelo];
    for (final m in _respaldo) {
      if (!modelos.contains(m)) modelos.add(m);
    }

    IaException? ultimo;
    for (final m in modelos) {
      try {
        return await _analizar(
          apiKey: apiKey,
          modelo: m,
          prompt: prompt,
          imagen: imagen,
          mime: mime,
        );
      } on IaException catch (e) {
        ultimo = e;
        // Un 404 (modelo cerrado para cuentas nuevas) o un 503 (saturación) se
        // resuelven probando el siguiente modelo. Cualquier otro error (clave,
        // cuota real, imagen bloqueada) se muestra tal cual.
        if (!e.modeloNoDisponible && !e.modeloSaturado) rethrow;
      }
    }
    throw ultimo!;
  }

  Future<String> _analizar({
    required String apiKey,
    required String modelo,
    required String prompt,
    required Uint8List imagen,
    required String mime,
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

    // Primero con búsqueda web; si el modelo o el plan no la soportan, se
    // reintenta sin ella: mejor una identificación sin internet que un error
    // seco. En el plan gratuito de los modelos 3.x la búsqueda no está
    // incluida y Google la rechaza con 429.
    final pensarPoco = _pensarPoco(modelo);
    try {
      return await _pedir(
        uri,
        apiKey,
        partes,
        conBusqueda: true,
        pensarPoco: pensarPoco,
      );
    } on IaException catch (e) {
      if (!e.herramientaNoSoportada) rethrow;
      return _pedir(
        uri,
        apiKey,
        partes,
        conBusqueda: false,
        pensarPoco: pensarPoco,
      );
    }
  }

  /// En los Gemini 3 con "thinking" el nivel por defecto es `medium`, que con
  /// una foto puede pasar de un minuto. `LOW` mantiene la calidad y baja el
  /// tiempo a ~30 s. Flash-Lite ya arranca en el mínimo.
  bool _pensarPoco(String modelo) {
    final m = modelo.toLowerCase();
    if (!m.startsWith('gemini-3') && !m.startsWith('gemini-4')) return false;
    return !m.contains('flash-lite');
  }

  Future<String> _pedir(
    Uri uri,
    String apiKey,
    List<Map<String, dynamic>> partes, {
    required bool conBusqueda,
    required bool pensarPoco,
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
                if (pensarPoco)
                  'thinkingConfig': {'thinkingLevel': 'LOW'},
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
    final mencionaHerramienta = minuscula.contains('search') ||
        minuscula.contains('tool') ||
        minuscula.contains('grounding');
    // En el plan gratuito de los modelos 3.x la búsqueda web no está incluida
    // y Google responde 429; se reintenta sin ella. Un 400 por herramienta
    // también.
    final sinHerramienta = conBusqueda &&
        ((r.statusCode == 400 && mencionaHerramienta) || r.statusCode == 429);
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
        return IaException(
          'La clave de Gemini no es válida o no tiene permisos. '
          'Cambiala en Ajustes → IA.'
          '${detalle.isEmpty ? '' : '\n\n$detalle'}',
        );
      case 404:
        return IaException(
          'El modelo de IA no está disponible para esta cuenta. '
          'Revisá el modelo en Ajustes → IA.'
          '${detalle.isEmpty ? '' : '\n\n$detalle'}',
          modeloNoDisponible: true,
        );
      case 429:
        return IaException(
          'Gemini rechazó la solicitud por límite de uso (429). '
          'Si la cuenta es nueva, el plan gratuito puede no incluir este '
          'modelo o la búsqueda web; probá otro modelo en Ajustes → IA o '
          'revisá la facturación en AI Studio.'
          '${detalle.isEmpty ? '' : '\n\n$detalle'}',
          herramientaNoSoportada: sinHerramienta,
        );
      case 503:
        return const IaException(
          'Los modelos de IA están saturados en este momento. '
          'Reintentá en unos minutos.',
          modeloSaturado: true,
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
