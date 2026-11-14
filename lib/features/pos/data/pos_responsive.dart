import 'package:flutter/material.dart';

/// Utilidades de layout para adaptar el POS a tablets pequeñas (Android
/// en horizontal) sin romper el escritorio.
///
/// Umbrales:
///  - ancho <= 720 dp: considera "pantalla pequeña" (tablet 7-8" horizontal)
///  - ancho <= 960 dp: considera "tablet media"

class PosResponsive {
  PosResponsive._();

  /// true si el ancho disponible es menor o igual a [umbral].
  static bool esPantallaPequena(BuildContext context, {double umbral = 720}) {
    return MediaQuery.sizeOf(context).width <= umbral;
  }

  /// true si es una tablet (ancho entre 600 y 1024 dp).
  static bool esTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w > 600 && w <= 1024;
  }

  /// Orientación actual.
  static bool esHorizontal(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  /// Tamaño mínimo de toque recomendado (48 dp) para accesibilidad táctil.
  static const double minToque = 48.0;

  /// Padding reducido para pantallas pequeñas.
  static double padding(BuildContext context) {
    return esPantallaPequena(context) ? 12.0 : 20.0;
  }

  /// Espaciado entre elementos del grid.
  static double gridSpacing(BuildContext context) {
    return esPantallaPequena(context) ? 8.0 : 10.0;
  }

  /// Máximo ancho de celda del grid de mesas.
  static double maxCrossAxisExtent(BuildContext context) {
    return esPantallaPequena(context) ? 150.0 : 130.0;
  }

  /// Ancho del panel de comandas en la pantalla de comanda.
  static double panelComandaAncho(BuildContext context) {
    if (esPantallaPequena(context)) {
      return 320.0; // menos ancho, deja más al catálogo
    }
    return 380.0;
  }

  /// Fuente de título de tarjeta.
  static double tituloTamano(BuildContext context) {
    return esPantallaPequena(context) ? 15.0 : 18.0;
  }

  /// Fuente de texto secundario.
  static double subtituloTamano(BuildContext context) {
    return esPantallaPequena(context) ? 11.0 : 13.0;
  }

  /// Altura mínima de botones táctiles.
  static double botonAltura(BuildContext context) {
    return esPantallaPequena(context) ? 48.0 : 44.0;
  }
}
