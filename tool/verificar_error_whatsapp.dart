// Verifica la lógica de _errorDeRespuesta() de whatsapp_repository.dart.
//
// No la importa: la reimplementa tal cual (con jsonDecode de dart:convert, que
// sí está disponible sin .dart_tool) para poder correrla en una máquina sin
// Flutter ni dependencias resueltas.
//
// Uso:  dart run tool/verificar_error_whatsapp.dart

import 'dart:convert';

/// Copia exacta de WhatsappRepository._errorDeRespuesta, con el body ya leído.
String errorDeRespuesta(int status, String body) {
  var detalle = '';
  try {
    if (body.isNotEmpty) {
      // Plan B por defecto: el cuerpo crudo. El JSON solo pisa ese valor si
      // viene con la clave "error".
      detalle = body.trim();
      try {
        final j = jsonDecode(body);
        if (j is Map && j['error'] != null) detalle = j['error'].toString();
      } catch (_) {
        // No es JSON: se conserva el cuerpo crudo.
      }
    }
  } catch (_) {
    // body ilegible: nos quedamos solo con el status.
  }
  detalle = detalle.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (detalle.length > 200) detalle = '${detalle.substring(0, 200)}…';
  return detalle.isEmpty ? 'HTTP $status' : 'HTTP $status: $detalle';
}

int fallos = 0;
void check(String etiqueta, String obtenido, String esperado) {
  if (obtenido == esperado) {
    print('  OK    $etiqueta');
  } else {
    print('  FALLA $etiqueta');
    print('         esperado: "$esperado"');
    print('         obtenido: "$obtenido"');
    fallos++;
  }
}

void main() {
  print('=== Como se ve el motivo en la bandeja ===');

  // 413: el caso de hoy. Sin el handler global, express devolvia HTML y a veces
  // el cuerpo llegaba vacío.
  check('413 con cuerpo vacío (el caso real de hoy)',
      errorDeRespuesta(413, ''), 'HTTP 413');

  // 413 ya con el handler global: llega JSON con el mensaje.
  check('413 con JSON del handler global',
      errorDeRespuesta(413, '{"error":"request entity too large"}'),
      'HTTP 413: request entity too large');

  // 413 con HTML: cae al plan B, se usa el body crudo.
  check('413 con HTML de express',
      errorDeRespuesta(413, '<html>\n  <body>Payload Too Large</body>\n</html>'),
      'HTTP 413: <html> <body>Payload Too Large</body> </html>');

  print('');
  print('=== Los otros fallos que antes salían todos como "Error de conexion" ===');
  check('401 sin cuerpo', errorDeRespuesta(401, ''), 'HTTP 401');
  check('401 con JSON',
      errorDeRespuesta(401, '{"error":"Unauthorized - Token requerido"}'),
      'HTTP 401: Unauthorized - Token requerido');
  check('503 sin cuerpo', errorDeRespuesta(503, ''), 'HTTP 503');
  check('500 con texto plano',
      errorDeRespuesta(500, 'No hay grupo configurado.'),
      'HTTP 500: No hay grupo configurado.');

  print('');
  print('=== Robustez del formato ===');
  check('JSON que no trae "error" cae al body crudo',
      errorDeRespuesta(500, '{"otra":"cosa"}'), 'HTTP 500: {"otra":"cosa"}');
  check('JSON que no es objeto',
      errorDeRespuesta(500, '[1,2,3]'), 'HTTP 500: [1,2,3]');
  check('solo espacios se consideran vacío',
      errorDeRespuesta(500, '   \n  '), 'HTTP 500');

  // El texto que va a la columna ultimo_error no debería crecer sin control:
  // es una columna de texto y se muestra en la bandeja.
  final largo = 'x' * 900;
  final r = errorDeRespuesta(500, '{"error":"$largo"}');
  final cortado = r.length == 'HTTP 500: '.length + 200 + 1; // +1 del ellipsis
  print('  ${cortado ? "OK   " : "FALLA"} cuerpo de 900 chars se recorta a ${r.length} (esperado $cortado)');
  if (!cortado) fallos++;
  print('  ${r.endsWith('…') ? "OK   " : "FALLA"} el recorte termina en elipsis unicode');
  if (!r.endsWith('…')) fallos++;

  print('');
  if (fallos == 0) {
    print('Todo OK: el motivo real llega a la bandeja');
  } else {
    print('FALLARON $fallos verificaciones');
  }
}