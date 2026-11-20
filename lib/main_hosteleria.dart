import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/errors/error_widget_app.dart';
import 'core/logging/log_bridge.dart';
import 'features/hosteleria/data/hostel_sqlite_backend.dart';
import 'features/hosteleria/presentation/hosteleria_app.dart';

/// Punto de entrada de Lycoris Hosteleria (independiente de inventario y POS).
///
/// Usa SQLite local por defecto (archivo `.db` junto al ejecutable) para
/// pruebas sin tocar la base de datos real de PostgreSQL.
///
/// Build: `flutter build windows --release -t lib/main_hosteleria.dart`.
void main() {
  // Inicializar FFI de SQLite (requerido en desktop con sqflite_common_ffi).
  SqliteDbBackend.initFFI();

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Que un error de render se vea como un aviso legible en vez de un
      // cuadro gris sin explicación (ver core/errors/error_widget_app.dart).
      instalarErrorWidgetDeApp();
      await LogBridge.instance.start();

      runApp(
        const ProviderScope(
          child: HosteleriaApp(),
        ),
      );
    },
    (error, stackTrace) {
      LogBridge.instance.push('$error\n$stackTrace');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
        LogBridge.instance.push(line);
      },
    ),
  );
}