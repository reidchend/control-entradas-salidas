import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gemini_cuota.dart';
import 'gemini_modelos.dart';

/// Error del servicio de IA con un mensaje ya listo para mostrar al usuario.
class IaException implements Exception {
  const IaException(
    this.mensaje, {
    this.herramientaNoSoportada = false,
    this.modeloNoDisponible = false,
    this.modeloSaturado = false,
    this.limiteCuota,
  });

  final String mensaje;

  /// `true` cuando el error fue porque el modelo no acepta la herramienta de
  /// búsqueda: el llamador reintenta sin ella.
  final bool herramientaNoSoportada;

  /// `true` cuando el modelo configurado ya no existe para esta cuenta (por
  /// ejemplo, los 2.5 en proyectos nuevos): el llamador prueba el respaldo.
  final bool modeloNoDisponible;

  /// `true` cuando Google respondió 503 (saturación) o 429 de cuota después
  /// de reintentar sin la búsqueda web: el llamador salta a otro modelo antes
  /// de rendirse. La cuota es por modelo, así que un 429 no significa que
  /// todos los demás lo estén.
  final bool modeloSaturado;

  /// Límite que Google reportó para el modelo en el 429, si lo trae (por
  /// ejemplo 250 por día). No es "intentos restantes", es el tope total del
  /// cupo; con el contador local da el saldo aproximado.
  final int? limiteCuota;

  @override
  String toString() => mensaje;
}

/// Cliente mínimo de Gemini para analizar una imagen.
///
/// Usa la API REST (`generateContent`) con la herramienta de búsqueda de
/// Google cuando el plan la incluye: el modelo mira la foto, busca
/// marca/modelo en la web y devuelve un texto (se le pide JSON). Si la
/// búsqueda no está disponible, reintenta sin ella. Si el modelo se queda sin
/// cuota o ya no existe, baja por la cadena de respaldo y después por todos
/// los modelos que la API acepte para la clave. No se agrega SDK: `http` ya
/// está en el proyecto.
class GeminiVision {
  GeminiVision({http.Client? cliente, this.cuota})
      : _cliente = cliente ?? http.Client(),
        _propio = cliente == null;

  final http.Client _cliente;
  final bool _propio;

  /// Si se pasa, cada intento exitoso se suma al contador local de cuota y el
  /// límite que Google reporte en un 429 queda guardado, para poder mostrar en
  /// Ajustes → IA cuánto del cupo diario ya se usó.
  final GeminiCuota? cuota;

  /// Libera el cliente HTTP si lo creó este objeto.
  void cerrar() {
    if (_propio) _cliente.close();
  }

  /// Respaldos fijos, probados de entrada sin consultar a la API.
  ///
  /// Google cerró los 2.5 para proyectos nuevos y recomienda 3.8 Flash. Si ese
  /// devuelve 503 o se le acaba la cuota, Flash-Lite suele tener más
  /// disponibilidad y tarda lo mismo. Si tampoco alcanza, se consulta el
  /// listado de modelos de la clave (ver [GeminiModelos]).
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
    // Cadena rápida: el modelo elegido más los dos respaldos fijos.
    final cadena = <String>[modelo];
    for (final m in _respaldo) {
      if (!cadena.contains(m)) cadena.add(m);
    }

    try {
      return await _probarCadena(
        cadena,
        apiKey: apiKey,
        prompt: prompt,
        imagen: imagen,
        mime: mime,
      );
    } on IaException catch (e) {
      // Un 404 (modelo cerrado para cuentas nuevas), un 503 (saturación) o
      // un 429 de cuota se resuelven probando otro modelo. Cualquier otro
      // error (clave inválida, imagen bloqueada) se muestra tal cual.
      if (!e.modeloNoDisponible && !e.modeloSaturado) rethrow;

      // La cuota es por modelo: un 429 en el configurado no significa que
      // el resto lo estén. Se le pide a la API qué modelos acepta esta
      // clave y se prueban todos, del más conveniente al menos.
      final extras = await GeminiModelos().disponibles(_cliente, apiKey);
      final resto = <String>[
        for (final m in extras)
          if (!cadena.contains(m)) m,
      ];
      if (resto.isEmpty) rethrow;
      try {
        return await _probarCadena(
          resto,
          apiKey: apiKey,
          prompt: prompt,
          imagen: imagen,
          mime: mime,
          tolerarTodo: true,
        );
      } on IaException catch (ultimo) {
        throw IaException(
          '${ultimo.mensaje}\n\n'
          'Se probaron ${cadena.length + resto.length} modelos de la cuenta '
          'y ninguno respondió.',
          modeloNoDisponible: ultimo.modeloNoDisponible,
          modeloSaturado: ultimo.modeloSaturado,
        );
      }
    }
  }

  /// Prueba los [modelos] en orden y devuelve el primero que responda.
  ///
  /// El que sobra se propaga: el que llama decide si hay más cadena (con
  /// [tolerarTodo] se sigue probando igual, para no frenar la cadena
  /// completa por un modelo que la cuenta no tiene habilitado).
  Future<String> _probarCadena(
    List<String> modelos, {
    required String apiKey,
    required String prompt,
    required Uint8List imagen,
    required String mime,
    bool tolerarTodo = false,
  }) async {
    IaException? ultimo;
    for (final m in modelos) {
      try {
        final texto = await _analizar(
          apiKey: apiKey,
          modelo: m,
          prompt: prompt,
          imagen: imagen,
          mime: mime,
        );
        await cuota?.registrarUso(m);
        return texto;
      } on IaException catch (e) {
        final limite = e.limiteCuota;
        if (limite != null) await cuota?.registrarLimite(m, limite);
        ultimo = e;
        if (tolerarTodo) continue;
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
      case 429: {
        final datos = _cuotaDe(r.body);
        return IaException(
          'Gemini rechazó la solicitud por límite de uso (429). '
          '${datos.limite == null ? '' : 'El tope es de ${datos.limite} por modelo al día. '}'
          'Si la cuenta es nueva, el plan gratuito puede no incluir este '
          'modelo o la búsqueda web; probá otro modelo en Ajustes → IA o '
          'revisá la facturación en AI Studio.'
          '${datos.espera == null ? '' : '\n\nEsperá ${datos.espera!.inSeconds} s y volvé a intentar.'}'
          '${detalle.isEmpty ? '' : '\n\n$detalle'}',
          herramientaNoSoportada: sinHerramienta,
          // Después de agotar el reintento sin búsqueda, esto es cuota de
          // verdad: se prueban el resto de los modelos antes de rendirse.
          modeloSaturado: !sinHerramienta,
          limiteCuota: datos.limite,
        );
      }
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

  /// Tope y espera que Google detalla en un 429.
  ///
  /// No son "intentos restantes" (Google nunca los publica), pero el tope es
  /// el dato que hace falta para que el contador local de `GeminiCuota` muestre
  /// "37 de 250 usadas hoy" en lugar de un número sin contexto.
  ({int? limite, Duration? espera}) _cuotaDe(String cuerpo) {
    int? limite;
    Duration? espera;
    try {
      final data = jsonDecode(cuerpo) as Map<String, dynamic>;
      final detalles = (data['error'] as Map<String, dynamic>?)?['details'];
      for (final d in (detalles as List? ?? const [])) {
        final m = d is Map<String, dynamic> ? d : null;
        if (m == null) continue;
        final tipo = m['@type'] as String? ?? '';
        if (tipo.contains('QuotaFailure')) {
          final violaciones = m['violations'] as List? ?? const [];
          final v = violaciones.isNotEmpty ? violaciones.first : null;
          if (v is Map<String, dynamic>) {
            final tope = v['quotaLimit'];
            if (tope is Map<String, dynamic>) {
              final n = tope['limit'];
              if (n is num) limite = n.toInt();
            }
            // A veces el tope viene solo en el texto de la descripción.
            limite ??= _numeroDe(v['description'] as String?);
          }
        } else if (tipo.contains('RetryInfo')) {
          final texto = m['retryDelay'] as String?;
          final seg = texto == null
              ? null
              : num.tryParse(texto.replaceAll(RegExp('[^0-9.]'), ''));
          if (seg != null) espera = Duration(seconds: seg.ceil());
        }
      }
    } catch (_) {
      // Cuerpo que no es JSON: se ignora, el mensaje base ya alcanza.
    }
    return (limite: limite, espera: espera);
  }

  /// Primer entero de un texto como «con un límite de 250 peticiones por día».
  int? _numeroDe(String? texto) {
    if (texto == null) return null;
    final m = RegExp(r'\b(\d{2,9})\b').firstMatch(texto);
    return m == null ? null : int.tryParse(m.group(1)!);
  }
}
