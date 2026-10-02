import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/logging/log_bridge.dart';
import 'features/hosteleria/presentation/hosteleria_app.dart';

/// Punto de entrada de Lycoris Hosteleria (independiente de inventario y POS).
///
/// Comparte la base de datos remota (PostgreSQL) con el POS; reutiliza las
/// habitaciones de `pos_habitaciones` y agrega sus tablas propias
/// (`hosteleria_huespedes`, `hosteleria_reservas`).
/// Build: `flutter build web --release -t lib/main_hosteleria.dart`.
void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
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