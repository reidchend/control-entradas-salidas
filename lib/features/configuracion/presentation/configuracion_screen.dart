import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../pos/presentation/config_screen.dart';
import 'widgets/categorias_tab.dart';
import 'widgets/productos_tab.dart';
import 'widgets/proveedores_tab.dart';
import 'widgets/sistema_tab.dart';
import 'widgets/periodos_tab.dart';
import 'widgets/usuarios_tab.dart';

/// Pantalla de Configuración / Ajustes.
///
/// Pestañas: Categorías, Productos, Proveedores, Sistema, Periodos y —solo
/// para nivel admin/desarrollador— Usuarios. Incluye un botón para abrir la
/// configuración del POS desde este módulo (administrativo).
class ConfiguracionScreen extends ConsumerStatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  ConsumerState<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends ConsumerState<ConfiguracionScreen> {
  bool _verPos = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_verPos) {
      return ConfigScreen(onBack: () => setState(() => _verPos = false));
    }

    final session = ref.watch(sessionProvider);
    final esAdmin = session is Authenticated && session.esAdmin;

    final tabs = <_TabDef>[
      const _TabDef('Categorías', Icons.category_outlined, CategoriasTab()),
      const _TabDef('Productos', Icons.inventory_2_outlined, ProductosTab()),
      const _TabDef(
          'Proveedores', Icons.local_shipping_outlined, ProveedoresTab()),
      const _TabDef('Sistema', Icons.settings_outlined, SistemaTab()),
      const _TabDef('Periodos', Icons.calendar_month_outlined, PeriodosTab()),
      if (esAdmin)
        const _TabDef(
            'Usuarios', Icons.manage_accounts_outlined, UsuariosTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Text('Ajustes',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _verPos = true),
                  icon: const Icon(Icons.point_of_sale_outlined),
                  label: const Text('Configuración del POS'),
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: scheme.outlineVariant,
            indicatorColor: scheme.primary,
            labelColor: scheme.primary,
            unselectedLabelColor: scheme.onSurfaceVariant,
            tabs: [
              for (final t in tabs)
                Tab(icon: Icon(t.icon), text: t.label),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [for (final t in tabs) t.child],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabDef {
  const _TabDef(this.label, this.icon, this.child);

  final String label;
  final IconData icon;
  final Widget child;
}
