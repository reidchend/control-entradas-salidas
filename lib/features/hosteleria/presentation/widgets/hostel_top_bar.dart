import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/state/theme_controller.dart';
import '../../../../core/theme/app_theme.dart';

/// Barra superior de Hostelería con el mismo estilo (gradiente) que el header
/// del resto de módulos: icono, título, operador y acciones.
class HostelTopBar extends ConsumerWidget {
  const HostelTopBar({
    super.key,
    required this.nombreOperador,
    required this.onSync,
    required this.onLogout,
  });

  final String nombreOperador;
  final VoidCallback onSync;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modo = ref.watch(themeControllerProvider);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            appColor(context, 'header_bg'),
            appColor(context, 'header_bg_2'),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(color: appColor(context, 'border')),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.hotel_outlined,
            size: 26,
            color: appColor(context, 'header_icon'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hostelería',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: appColor(context, 'header_title'),
                  ),
                ),
                Text(
                  nombreOperador.isEmpty
                      ? 'Recepción'
                      : 'Recepción · $nombreOperador',
                  style: TextStyle(
                    fontSize: 12,
                    color: appColor(context, 'header_subtitle'),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            color: appColor(context, 'header_subtitle'),
            tooltip: 'Sincronizar',
            onPressed: onSync,
          ),
          IconButton(
            icon: Icon(modo == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            color: appColor(context, 'header_subtitle'),
            tooltip: 'Tema',
            onPressed: () =>
                ref.read(themeControllerProvider.notifier).toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            color: appColor(context, 'header_subtitle'),
            tooltip: 'Cerrar sesión',
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}
