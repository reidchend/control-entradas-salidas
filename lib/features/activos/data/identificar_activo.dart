import 'dart:convert';
import 'dart:typed_data';

import '../../../core/ia/gemini_cuota.dart';
import '../../../core/ia/gemini_vision.dart';
import 'activo_identificado.dart';

/// Pide a Gemini que mire la foto del artículo y devuelva un JSON con lo
/// necesario para precargar el alta de activo. Si el plan incluye la búsqueda
/// web, además confirma marca/modelo/precio con Google Search.
///
/// Si se pasa [cuota], cada identificación se suma al contador local de uso
/// por modelo (para mostrar cuánto del cupo diario ya se gastó).
Future<ActivoIdentificado> identificarActivoDesdeFoto({
  required Uint8List imagen,
  required String apiKey,
  required String modelo,
  GeminiCuota? cuota,
}) async {
  final vision = GeminiVision(cuota: cuota);
  final String texto;
  try {
    texto = await vision.analizarImagen(
      apiKey: apiKey,
      modelo: modelo,
      prompt: _prompt,
      imagen: imagen,
    );
  } finally {
    vision.cerrar();
  }
  final datos = ActivoIdentificado.desdeMap(_extraerJson(texto));
  if (datos.nombre.isEmpty) {
    throw const IaException(
      'La IA no pudo reconocer el artículo. Probá con más luz y el objeto '
      'completo en la foto.',
    );
  }
  return datos;
}

const _prompt = '''
Sos un asistente de inventario de una empresa. Analizá la foto del artículo y
devolvé ÚNICAMENTE un objeto JSON válido, sin markdown ni texto alrededor, con
exactamente estas claves:

{
  "nombre": "nombre corto y comercial, incluyendo la marca si se reconoce",
  "marca": "marca visible o deducida; cadena vacía si no se reconoce",
  "modelo": "modelo o referencia; cadena vacía si no se reconoce",
  "grupo": "grupo general: Electrónica, Electrodomésticos, Muebles, Herramientas, Menaje, Textiles u otro",
  "categoria": "categoría de activo fijo si se puede inferir; vacía si no",
  "descripcion": "una o dos frases con especificaciones visibles: material, color, capacidad, medidas",
  "valor_estimado_usd": 0,
  "confianza": 0.0
}

Reglas:
- Si la marca o el modelo son visibles (logo, etiqueta, placa), buscá ese
  producto en la web para confirmar especificaciones y precio de mercado.
- "valor_estimado_usd": número aproximado en dólares; 0 si no estás seguro.
- "confianza": número entre 0 y 1 sobre la identificación.
- No inventes datos. Si no reconocés el artículo, usá el nombre
  "Artículo sin identificar", confianza 0 y explicá en "descripcion" qué se ve.
''';

/// Extrae el primer objeto JSON del texto del modelo.
///
/// Aunque se le pide JSON puro, la búsqueda web a veces agrega texto o lo
/// envuelve en ```json; se tolera para no fallar por formato.
Map<String, dynamic> _extraerJson(String texto) {
  var limpio = texto.trim();
  final bloque = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
      .firstMatch(limpio);
  if (bloque != null) limpio = bloque.group(1)!.trim();

  final inicio = limpio.indexOf('{');
  final fin = limpio.lastIndexOf('}');
  if (inicio < 0 || fin <= inicio) {
    throw const IaException(
      'La IA no devolvió datos reconocibles. Probá de nuevo con otra foto.',
    );
  }

  try {
    final datos = jsonDecode(limpio.substring(inicio, fin + 1));
    if (datos is! Map<String, dynamic>) {
      throw const FormatException('No es un objeto');
    }
    return datos;
  } on IaException {
    rethrow;
  } catch (_) {
    throw const IaException(
      'La IA devolvió datos con un formato inesperado. Probá de nuevo.',
    );
  }
}
