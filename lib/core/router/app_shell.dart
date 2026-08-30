import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../auth/session_controller.dart';
import '../data/realtime_providers.dart';
import '../data/realtime_service.dart';
import '../data/supabase_providers.dart';
import '../state/theme_controller.dart';
import '../../features/historial/presentation/historial_screen.dart';
import '../../features/inventario/presentation/inventario_screen.dart';
import '../../features/producciones/presentation/producciones_screen.dart';
import '../../features/requisiciones/presentation/requisiciones_screen.dart';
import '../../features/reportes/presentation/screens/reportes_screen.dart';
import '../../features/stock/presentation/stock_screen.dart';
import '../../features/validacion/presentation/validacion_screen.dart';
import '../../features/configuracion/presentation/configuracion_screen.dart';
import '../../features/whatsapp/presentation/bandeja_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
/// Shell principal — replica `usr/app_controller.py`:
/// - sin sesión → LoginScreen.
/// - con sesión → header custom (icono + título + subtítulo) sobre un
///   NavigationRail (escritorio) o NavigationBar + drawer (móvil),
///   todo con los colores de `usr/theme.py` (`get_theme`).
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const List<_NavDest> _destinos = [
    _NavDest(Icons.assessment_outlined, 'Reportes',
        'Ventas, movimientos y estadísticas', '/reportes'),
    _NavDest(Icons.shopping_cart_outlined, 'Inventario',
        'Gestión de existencias', '/inventario'),
    _NavDest(Icons.checklist_outlined, 'Validación',
        'Vincular entradas a facturas', '/validacion'),
    _NavDest(Icons.warehouse_outlined, 'Stock',
        'Control e inventario de productos y pesaje', '/stock'),
    _NavDest(Icons.factory_outlined, 'Producciones',
        'Recetas y órdenes de producción', '/producciones'),
    _NavDest(Icons.local_shipping_outlined, 'Requisiciones',
        'Gestión de traslados', '/requisiciones'),
    _NavDest(Icons.history_outlined, 'Historial',
        'Facturas y registro de entradas', '/historial'),
    _NavDest(Icons.settings_outlined, 'Ajustes',
        'Categorías y catálogo de productos', '/ajustes'),
    _NavDest(Icons.mail_outlined, 'Bandeja',
        'Mensajes y respuestas de WhatsApp', '/bandeja'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final themeMode = ref.watch(themeControllerProvider);
    final appTheme = buildAppTheme(mode: themeMode);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Control Entradas y Salidas',
      theme: appTheme.light(),
      darkTheme: appTheme.dark(),
      themeMode: themeMode,
      // Diálogos responsivos: en escritorio crecen (min 520, hasta 85% del
      // ancho con tope de 1000) para aprovechar pantallas grandes; en móvil
      // conservan el comportamiento por defecto de Material.
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
      home: session is Authenticated
          ? const _ShellAutenticado(destinos: _destinos)
          : const LoginScreen(),
    );
  }
}

class _ShellAutenticado extends ConsumerStatefulWidget {
  const _ShellAutenticado({required this.destinos});
  final List<_NavDest> destinos;

  @override
  ConsumerState<_ShellAutenticado> createState() => _ShellAutenticadoState();
}

class _ShellAutenticadoState extends ConsumerState<_ShellAutenticado> {
  int _index = 0;
  int _refreshTick = 0;
  List<RealtimeSubscription> _realtimeSubs = [];

  /// Botón de sincronizar del encabezado: remonta la pantalla activa para
  /// recargar sus datos.
  void _syncActual() {
    setState(() => _refreshTick++);
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    Future(() {
      final rt = ref.read(realtimeServiceProvider);
      if (rt != null) {
        _realtimeSubs = initRealtimeSubscriptions(rt, ref);
      }
    });
  }

  @override
  void dispose() {
    for (final sub in _realtimeSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final esEscritorio = ancho >= 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? AppColors.dark : AppColors.light;
    final dest = widget.destinos[_index];

    return Scaffold(
      key: _scaffoldKey,
      body: SafeArea(
        child: Column(
          children: [
            _AppHeader(
              destinos: widget.destinos,
              index: _index,
              colors: c,
              esEscritorio: esEscritorio,
              onSync: _syncActual,
              onToggleTheme: () => ref
                  .read(themeControllerProvider.notifier)
                  .toggle(),
              onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _color(c, 'surface'),
                        borderRadius: esEscritorio
                            ? const BorderRadius.only(
                                topLeft: Radius.circular(20))
                            : null,
                      ),
                      child: KeyedSubtree(
                        key: ValueKey('dest-${dest.ruta}-$_refreshTick'),
                        child: _DestinoPage(destino: dest),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: esEscritorio
          ? null
          : _NavBarMobile(
              destinos: widget.destinos,
              index: _index,
              colors: c,
              onSelect: (i) {
                if (i >= 3) {
                  _scaffoldKey.currentState?.openDrawer();
                } else {
                  setState(() => _index = i);
                }
              },
            ),
      drawer: _AppDrawer(
        destinos: widget.destinos,
        index: _index,
        colors: c,
        onSelect: (i) {
          setState(() => _index = i);
          Navigator.pop(context);
        },
      ),
    );
  }

  Color _color(Map<String, String> c, String key) =>
      Color(int.parse(c[key]!.replaceFirst('#', '0xFF')));
}

/// Header custom (app_controller.py `app_header`): bugb negro, ícono morado,
/// título 22 bold + subtítulo 12, indicador global de conexión y acciones.
class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.destinos,
    required this.index,
    required this.colors,
    required this.esEscritorio,
    required this.onSync,
    required this.onToggleTheme,
    required this.onOpenDrawer,
  });

  final List<_NavDest> destinos;
  final int index;
  final Map<String, String> colors;
  final bool esEscritorio;
  final VoidCallback onSync;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenDrawer;

  Color _color(String key) =>
      Color(int.parse(colors[key]!.replaceFirst('#', '0xFF')));

  @override
  Widget build(BuildContext context) {
    final dest = destinos[index];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_color('header_bg'), _color('header_bg_2')],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(color: _color('border')),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (esEscritorio)
            IconButton(
              icon: const Icon(Icons.menu),
              color: _color('header_title'),
              tooltip: 'Abrir menú',
              onPressed: onOpenDrawer,
            ),
          Icon(dest.icono, size: 26, color: _color('header_icon')),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dest.label,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _color('header_title'),
                ),
              ),
              Text(
                dest.subtitulo,
                style: TextStyle(
                  fontSize: 12,
                  color: _color('header_subtitle'),
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.sync),
            color: _color('header_subtitle'),
            tooltip: 'Sincronizar',
            onPressed: onSync,
          ),
          IconButton(
            icon: const Icon(Icons.brightness_6_outlined),
            color: _color('header_subtitle'),
            tooltip: 'Tema',
            onPressed: onToggleTheme,
          ),
        ],
      ),
    );
  }
}

/// Barra inferior móvil — `navigation_bar` de app_controller.py (4 ítems, el
/// último abre el drawer "Más").
class _NavBarMobile extends StatelessWidget {
  const _NavBarMobile({
    required this.destinos,
    required this.index,
    required this.colors,
    required this.onSelect,
  });

  final List<_NavDest> destinos;
  final int index;
  final Map<String, String> colors;
  final ValueChanged<int> onSelect;

  Color _color(String key) =>
      Color(int.parse(colors[key]!.replaceFirst('#', '0xFF')));

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      backgroundColor: _color('nav_bg'),
      indicatorColor: _color('drawer_active_bg'),
      selectedIndex: index > 3 ? 3 : index,
      onDestinationSelected: onSelect,
      destinations: [
        NavigationDestination(
            icon: Icon(destinos[0].icono), label: destinos[0].label),
        NavigationDestination(
            icon: Icon(destinos[1].icono), label: destinos[1].label),
        NavigationDestination(
            icon: Icon(destinos[2].icono), label: destinos[2].label),
        const NavigationDestination(icon: Icon(Icons.more_vert), label: 'Más'),
      ],
    );
  }
}

/// Drawer custom (overlay, lado izquierdo, tiles redondeados) —
/// `drawer_panel` + `_drawer_items` de app_controller.py.
class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.destinos,
    required this.index,
    required this.colors,
    required this.onSelect,
  });

  final List<_NavDest> destinos;
  final int index;
  final Map<String, String> colors;
  final ValueChanged<int> onSelect;

  Color _color(String key) =>
      Color(int.parse(colors[key]!.replaceFirst('#', '0xFF')));

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: _color('drawer_bg'),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 28, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 20),
                child: Text(
                  'Menú',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _color('drawer_on_surface'),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (var i = 0; i < destinos.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        child: Material(
                          color: i == index
                              ? _color('drawer_active_bg')
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            leading: Icon(
                              destinos[i].icono,
                              size: 22,
                              color: i == index
                                  ? _color('drawer_active_fg')
                                  : _color('drawer_inactive_fg'),
                            ),
                            title: Text(
                              destinos[i].label,
                              style: TextStyle(
                                fontSize: 15,
                                color: i == index
                                    ? _color('drawer_active_fg')
                                    : _color('drawer_inactive_fg'),
                                fontWeight: i == index
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onTap: () => onSelect(i),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinoPage extends StatelessWidget {
  const _DestinoPage({required this.destino});
  final _NavDest destino;

  @override
  Widget build(BuildContext context) {
    if (destino.ruta == '/reportes') {
      return const ReportesScreen();
    }
    if (destino.ruta == '/inventario') {
      return const InventarioScreen();
    }
    if (destino.ruta == '/validacion') {
      return const ValidacionScreen();
    }
    if (destino.ruta == '/requisiciones') {
      return const RequisicionesScreen();
    }
    if (destino.ruta == '/producciones') {
      return const ProduccionesScreen();
    }
    if (destino.ruta == '/stock') {
      return const StockScreen();
    }
    if (destino.ruta == '/historial') {
      return const HistorialScreen();
    }
    if (destino.ruta == '/ajustes') {
      return const ConfiguracionScreen();
    }
    if (destino.ruta == '/bandeja') {
      return const BandejaScreen();
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(destino.icono, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(destino.label,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Módulo pendiente (Fases 3-5)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NavDest {
  final IconData icono;
  final String label;
  final String subtitulo;
  final String ruta;
  const _NavDest(this.icono, this.label, this.subtitulo, this.ruta);
}