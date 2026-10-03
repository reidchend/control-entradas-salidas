import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/hostel_session.dart';
import 'hosteleria_screen.dart';
import 'widgets/hostel_login_view.dart';

/// Aplicación Lycoris Hosteleria — punto de entrada `lib/main_hosteleria.dart`.
///
/// Misma base de datos que el POS (PostgreSQL compartido): reutiliza las
/// habitaciones de `habitaciones` y agrega gestión propia de huéspedes y
/// reservas. Usa login propio de recepcionistas (grid + PIN, sin caja).
class HosteleriaApp extends ConsumerWidget {
  const HosteleriaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(hostelSessionProvider);
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
      home: sesion != null
          ? const HosteleriaScreen()
          : const HostelLoginView(),
    );
  }
}