import 'package:flutter/material.dart';

import '../../../core/updater/update_settings_card.dart';
import '../data/pos_session.dart';
import 'widgets/config_categorias_tab.dart';
import 'widgets/config_habitaciones_tab.dart';
import 'widgets/config_impresora_tab.dart';
import 'widgets/config_mesas_tab.dart';
import 'widgets/config_platos_tab.dart';
import 'widgets/config_tasa_tab.dart';
import 'widgets/config_usuarios_tab.dart';
import 'widgets/pos_top_bar.dart';

/// Configuración del POS (port de `ConfigPOSView` de config.py): pestañas de
/// cajeros, mesas, habitaciones, platos, categorías POS/sub-categorías, tasa
/// BCV e impresora (membrete/correlativo/dispositivo).
///
/// Reutilizable desde el módulo de inventario: si no hay [sesion] de POS
/// activa se muestra una barra simple con botón volver (sin cajero/logout).
class ConfigScreen extends StatelessWidget {
  const ConfigScreen({
    super.key,
    this.sesion,
    this.onBack,
    this.onLogout,
  });

  final PosSesionActiva? sesion;
  final VoidCallback? onBack;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final session = sesion;
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        body: Column(
          children: [
            if (session != null)
              PosTopBar(
                usuario: session.usuario,
                titulo: 'Configuración',
                onBack: onBack,
                onLogout: onLogout,
              )
            else
              _ConfigSinSesion(onBack: onBack),
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Cajeros', icon: Icon(Icons.person_outline)),
                Tab(text: 'Mesas', icon: Icon(Icons.table_bar_outlined)),
                Tab(
                  text: 'Habitaciones',
                  icon: Icon(Icons.hotel_outlined),
                ),
                Tab(text: 'Platos', icon: Icon(Icons.restaurant_outlined)),
                Tab(
                  text: 'Categorías',
                  icon: Icon(Icons.category_outlined),
                ),
                Tab(text: 'Tasa BCV', icon: Icon(Icons.currency_exchange)),
                Tab(text: 'Impresora', icon: Icon(Icons.print_outlined)),
                Tab(text: 'Actualización', icon: Icon(Icons.system_update)),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  ConfigUsuariosTab(),
                  ConfigMesasTab(),
                  ConfigHabitacionesTab(),
                  ConfigPlatosTab(),
                  ConfigCategoriasTab(),
                  ConfigTasaTab(),
                  ConfigImpresoraTab(),
                  _ActualizacionesTab(),
                ],
              ),
            ),          ],
        ),
      ),
    );
  }
}

/// Barra simple cuando se abre la config del POS fuera del POS (sin sesión).
class _ConfigSinSesion extends StatelessWidget {
  const _ConfigSinSesion({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Volver',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          const SizedBox(width: 4),
          Icon(Icons.point_of_sale_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Text(
            'Configuración del POS',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// Pestaña de actualizaciones (escritorio/Android).
class _ActualizacionesTab extends StatelessWidget {
  const _ActualizacionesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [UpdateSettingsCard()],
    );
  }
}
