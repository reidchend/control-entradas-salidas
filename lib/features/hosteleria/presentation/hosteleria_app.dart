import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/login_screen.dart';
import 'hosteleria_screen.dart';

/// Aplicación Lycoris Hosteleria — punto de entrada `lib/main_hosteleria.dart`.
///
/// Misma base de datos que el POS (PostgreSQL compartido): reutiliza las
/// habitaciones de `pos_habitaciones` y agrega gestión propia de huéspedes y
/// reservas. Usa el mismo login de operadores que la app de inventario.
class HosteleriaApp extends ConsumerWidget {
  const HosteleriaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final appTheme = buildAppTheme(mode: ThemeMode.light);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lycoris Hosteleria',
      theme: appTheme.light(),
      darkTheme: appTheme.dark(),
      themeMode: ThemeMode.light,
      builder: (context, child) {
        final ancho = MediaQuery.sizeOf(context).width;
        final esEscritorio = ancho >= 600;
        final constraints = esEscritorio
            ? BoxConstraints(
                minWidth: 520,
                maxWidth: math.min(ancho * 0.95, 1500),
              )
            : const BoxConstraints(minWidth: 280);
        return DialogTheme(
          data: Theme.of(context).dialogTheme.copyWith(constraints: constraints),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: session is Authenticated
          ? const HosteleriaScreen()
          : const LoginScreen(),
    );
  }
}