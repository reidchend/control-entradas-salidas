import 'dart:convert';

import 'package:http/http.dart' as http;

/// Modelos de Gemini que esta clave puede usar.
///
/// La identificación de activos baja por una cadena de respaldo si el modelo
/// configurado se queda sin cuota (429) o ya no existe para la cuenta (404).
/// Cuando eso pasa se le pregunta a la API qué modelos acepta la clave, para
/// que el salto no se limite a dos fijos escritos en el código: en el plan
/// gratuito la cuota es por modelo, así que un modelo agotado no significa que
/// todo lo demás lo esté.
class GeminiModelos {
  GeminiModelos();

  static const _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Listado por clave para no repetirlo en cada foto.
  static final Map<String, List<String>> _cache = {};

  /// Nombres de modelos generables (sin el prefijo `models/`), del más
  /// conveniente al menos. Vacío si el listado no se pudo leer.
  Future<List<String>> disponibles(http.Client cliente, String apiKey) async {
    final guardado = _cache[apiKey];
    if (guardado != null) return guardado;

    try {
      final r = await cliente
          .get(
            Uri.parse('$_base?pageSize=100'),
            headers: {'x-goog-api-key': apiKey},
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return const [];

      final data = jsonDecode(utf8.decode(r.bodyBytes));
      if (data is! Map<String, dynamic>) return const [];

      final lista = <String>[];
      for (final m in (data['models'] as List? ?? const [])) {
        if (m is! Map) continue;
        final nombre =
            ((m['name'] as String?) ?? '').replaceFirst('models/', '');
        final metodos = (m['supportedGenerationMethods'] as List?) ?? const [];
        if (nombre.isEmpty || !metodos.contains('generateContent')) continue;
        // La API lista también gemma, aqa y demás: solo interesan los Gemini.
        if (!nombre.toLowerCase().contains('gemini')) continue;
        lista.add(nombre);
      }

      lista.sort(_comparar);
      _cache[apiKey] = lista;
      return lista;
    } catch (_) {
      // Sin listado no se pierde nada: quien llama se rinde con el error real.
      return const [];
    }
  }

  /// Flash primero (más rápidos y con más disponibilidad), después lite, luego
  /// el resto y al final los experimentales. Dentro de un grupo, el nombre
  /// descendente deja lo más nuevo primero (3.8 antes que 2.5).
  static int _comparar(String a, String b) {
    final porGrupo = _prioridad(a).compareTo(_prioridad(b));
    if (porGrupo != 0) return porGrupo;
    return b.compareTo(a);
  }

  static int _prioridad(String nombre) {
    final s = nombre.toLowerCase();
    if (s.contains('exp') || s.contains('preview')) return 4;
    if (s.contains('lite')) return 2;
    if (s.contains('flash')) return 1;
    return 3; // pro y el resto
  }
}
