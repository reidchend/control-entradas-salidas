/// Configuración de idioma compartida por las tres apps (inventario, POS y
/// hostelería).
///
/// Los widgets de Material que traen sus propios textos (`showDatePicker`,
/// `showTimePicker`, diálogos de error de validación, etc.) usan
/// `MaterialLocalizations.of(context)`. Sin estos delegados Flutter solo
/// registra la variante inglesa, por eso el calendario aparecía en inglés.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

abstract final class AppLocalizations {
  /// Idioma forzado de la interfaz (el usuario trabaja en español).
  static const Locale locale = Locale('es');

  /// Idiomas que la app sabe mostrar.
  static const List<Locale> supportedLocales = [Locale('es'), Locale('en')];

  /// Delegados necesarios para fecha, widgets base y Cupertino.
  static const List<LocalizationsDelegate<dynamic>> delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}
