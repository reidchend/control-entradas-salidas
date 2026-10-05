import 'dart:convert';

import 'descubrimiento_error.dart';

/// Saca la URL del servidor del cuerpo de un Gist.
///
/// Va aparte de `DescubridorServidor` por responsabilidad: esto es entender el
/// formato que publica `tool/iniciar_tunnel_api.js`, y no hay red ni caché de
/// por medio. Si el formato del Gist cambia, este es el único archivo que hay
/// que tocar, y se puede ejercitar sin levantar un servidor.
///
/// Acá termina el parseo, y por diseño lanza [DescubrimientoError] en vez de
/// devolver `null`: un Gist que responde y publica algo inservible no mejora
/// reintentando, así que el llamador tiene que enterarse para avisar que hay
/// que republicar en la PC servidor.
String leerUrlPublicada(String cuerpoGist) {
  final Map<String, dynamic> gist;
  try {
    gist = jsonDecode(cuerpoGist) as Map<String, dynamic>;
  } catch (_) {
    throw const DescubrimientoError('El Gist devolvió una respuesta ilegible.');
  }

  final files = gist['files'] as Map<String, dynamic>?;
  final archivo = files?[_nombreArchivo] as Map<String, dynamic>?;
  final contenido = archivo?['content']?.toString();
  if (contenido == null || contenido.isEmpty) {
    throw const DescubrimientoError(
      'El Gist no tiene el archivo de la URL. '
      'Falta ejecutar tool/iniciar_tunnel_api.js en la PC servidor.',
    );
  }

  Map<String, dynamic> datos;
  try {
    datos = jsonDecode(contenido) as Map<String, dynamic>;
  } catch (_) {
    throw const DescubrimientoError(
      'api_url.json no contiene un JSON válido.',
    );
  }

  final url = datos['url']?.toString().trim() ?? '';
  if (url.isEmpty) {
    throw const DescubrimientoError('api_url.json no tiene el campo "url".');
  }
  // Solo https: por HTTP plano la conexión no viaja cifrada y Android 9+ la
  // bloquea. Además, una URL rara acá sería un vector de inyección.
  if (!url.startsWith('https://')) {
    throw DescubrimientoError(
      'La URL publicada ("$url") no empieza con https://.',
    );
  }
  return url;
}

/// Nombre del archivo dentro del Gist.
///
/// Va como constante propia y no como [AppConfig.apiUrlFile] para que este
/// archivo no dependa de la app completa: se importa en tests sueltos.
const _nombreArchivo = 'api_url.json';