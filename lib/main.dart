import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/logging/log_bridge.dart';
import 'core/network/postgres_client.dart';
import 'core/router/app_shell.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await LogBridge.instance.start();

      // Configurar PostgreSQL pool (no-op si falta la URL).
      await initializePostgres();

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