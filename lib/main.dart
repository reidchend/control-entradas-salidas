import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/logging/log_bridge.dart';
import 'core/router/app_shell.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await LogBridge.instance.start();

      // No se inicializa el pool acá a propósito: sin URL configurada
      // `initializePostgres()` lanza, y hacerlo antes de `runApp` dejaría
      // la app en blanco sin llegar a la pantalla donde se configura.
      // `postgresPoolProvider` lo crea de forma perezosa en el primer uso.

      runApp(
        const ProviderScope(
          child: AppShell(),
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