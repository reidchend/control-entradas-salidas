import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/state/theme_controller.dart';
import '../../../../core/updater/update_settings_card.dart';
import '../../../configuracion/presentation/dialogs/db_config_dialog.dart';

/// Pestaña "Sistema" de la configuración de Hostelería: actualizaciones,
/// conexión a PostgreSQL y apariencia (tema claro/oscuro).
class HostelConfigSistemaTab extends ConsumerWidget {
  const HostelConfigSistemaTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = ref.watch(themeControllerProvider) == ThemeMode.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const UpdateSettingsCard(),
        _section(
          scheme,
          title: 'Base de datos',
          subtitle: 'Host, puerto, usuario y contraseña del servidor '
              'PostgreSQL. Se guarda en este equipo; no requiere recompilar.',
          icon: Icons.dns_outlined,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.settings_ethernet),
              label: const Text('Configurar conexión'),
              onPressed: () => showDbConfigDialog(context),
            ),
          ],
        ),
        _section(
          scheme,
          title: 'Apariencia',
          subtitle: 'Cambie entre el tema claro y oscuro de la aplicación.',
          icon: Icons.brightness_6,
          children: [
            Row(
              children: [
                Text(
                  'Tema:',
                  style:
                      TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: isDark,
                  onChanged: (_) =>
                      ref.read(themeControllerProvider.notifier).toggle(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _section(
    ColorScheme scheme, {
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: scheme.onPrimaryContainer, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}
