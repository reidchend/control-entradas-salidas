import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'pos_screen.dart';

/// Aplicación POS standalone — punto de entrada `lib/main_pos.dart`.
///
/// Misma base de datos (Supabase) que la app de inventario, pero con su propia
/// base local (IndexedDB). Arranca el motor de sync POS al inicio (catálogo de
/// venta + tablas pos_* + subida de movimientos) y muestra el login PIN.
///
/// La sesión NO se cierra al perder foco/minimizar la ventana: el cajero
/// retoma el POS donde lo dejó. Su turno solo se cierra desde el diálogo
/// 'Cerrar turno'.
class PosApp extends ConsumerStatefulWidget {
  const PosApp({super.key});

  @override
  ConsumerState<PosApp> createState() => _PosAppState();
}

class _PosAppState extends ConsumerState<PosApp> {
  @override
  Widget build(BuildContext context) {
    // El POS se usa siempre en oscuro (colores del POS portado de Flet).
    final appTheme = buildAppTheme(mode: ThemeMode.dark);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lycoris POS',
      theme: appTheme.light(),
      darkTheme: appTheme.dark(),
      themeMode: ThemeMode.dark,
      // Diálogos responsivos: en escritorio crecen (min 520, hasta 85% del
      // ancho con tope de 1000); en móvil conservan el comportamiento por
      // defecto de Material (igual que app_shell.dart).
      builder: (context, child) {
        final ancho = MediaQuery.sizeOf(context).width;
        final esEscritorio = ancho >= 600;
        final constraints = esEscritorio
            ? BoxConstraints(
                minWidth: 520,
                maxWidth: math.min(ancho * 0.85, 1000),
              )
            : const BoxConstraints(minWidth: 280);
        return DialogTheme(
          data: Theme.of(context).dialogTheme.copyWith(constraints: constraints),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const PosScreen(),
    );
  }
}
