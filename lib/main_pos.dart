import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/logging/log_bridge.dart';
import 'features/pos/presentation/pos_app.dart';

/// Punto de entrada de la aplicación POS (independiente de la app de
/// inventario). Comparte la base de datos remota (PostgreSQL pooler) y mantiene su
/// propia base local. Build: `flutter build web --release -t lib/main_pos.dart`.
void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await LogBridge.instance.start();

      // No se inicializa el pool acá a propósito: sin base configurada
      // `initializePostgres()` lanza, y hacerlo antes de `runApp` dejaría la
      // ventana en blanco, sin login ni forma de configurar la conexión.
      // `postgresPoolProvider` lo crea de forma perezosa en el primer uso, y
      // la pantalla de login ofrece "Configurar conexión" cuando falta.
      runApp(
        const ProviderScope(
          child: PosApp(),
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
