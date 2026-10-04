import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configuracion/presentation/widgets/usuarios_tab.dart';
import '../../pos/presentation/widgets/config_habitaciones_tab.dart';
import '../data/hostel_session.dart';
import 'widgets/hostel_config_sistema_tab.dart';

/// Configuración de Hostelería — solo para usuarios admin/desarrollador.
///
/// Pestañas: Habitaciones (compartidas con el POS), Usuarios (directorio
/// central) y Sistema (actualizaciones, base de datos y apariencia). El
/// acceso se controla desde [HostelTopBar] y se vuelve a validar aquí.
class HosteleriaConfigScreen extends ConsumerWidget {
  const HosteleriaConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(hostelSessionProvider);
    final esAdmin = sesion?.esAdmin ?? false;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Configuración · Hostelería'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Habitaciones', icon: Icon(Icons.hotel_outlined)),
              Tab(
                text: 'Usuarios',
                icon: Icon(Icons.manage_accounts_outlined),
              ),
              Tab(text: 'Sistema', icon: Icon(Icons.settings_outlined)),
            ],
          ),
        ),
        body: !esAdmin
            ? const _AccesoRestringido()
            : const TabBarView(
                children: [
                  ConfigHabitacionesTab(),
                  UsuariosTab(),
                  HostelConfigSistemaTab(),
                ],
              ),
      ),
    );
  }
}

class _AccesoRestringido extends StatelessWidget {
  const _AccesoRestringido();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 64, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          const Text(
            'Acceso restringido',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Solo los administradores pueden ver esta sección.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
