import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ancho recomendado para el contenido de un modal. Aprovecha casi todo el
/// ancho de la ventana en escritorio, con tope para pantallas muy grandes
/// (4K). En móvil se acerca al ancho total de la pantalla.
///
/// Usar como reemplazo de los `SizedBox(width: N)`/`BoxConstraints(maxWidth: N)`
/// fijos dentro de los diálogos para que se adapten al tamaño de la ventana.
double modalContentWidth(
  BuildContext context, {
  double factor = 0.92,
  double max = 1200,
}) {
  final ancho = MediaQuery.sizeOf(context).width;
  return math.min(ancho * factor, max);
}