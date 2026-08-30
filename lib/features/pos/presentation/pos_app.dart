import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/pos_session.dart';
import 'pos_screen.dart';

/// Aplicación POS standalone — punto de entrada `lib/main_pos.dart`.
///
/// Misma base de datos (Supabase) que la app de inventario, pero con su propia
/// base local (IndexedDB). Arranca el motor de sync POS al inicio (catálogo de
/// venta + tablas pos_* + subida de movimientos) y muestra el login PIN.
class PosApp extends ConsumerStatefulWidget {
  const PosApp({super.key});

  @override
  ConsumerState<PosApp> createState() => _PosAppState();
}

class _PosAppState extends ConsumerState<PosApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // App perdió foco o se minimizó: se libera la sesión en memoria pero el
      // turno de caja NO se cierra en BD. Así, al volver a entrar, el cajero
      // retoma SU turno donde quedó (evita cierres fantasma al minimizar,
      // bloquear pantalla o al actualizar/recompilar la app).
      ref.read(posSessionProvider.notifier).salirSinCerrar();
    }
  }

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
