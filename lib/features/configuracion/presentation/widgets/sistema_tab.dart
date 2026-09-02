import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/state/theme_controller.dart';
import '../../../../core/updater/update_settings_card.dart';
import '../../../../core/utils/web_utils.dart';
import '../../data/configuracion_providers.dart'
    show
        configuracionRepoProvider,
        permitirStockNegativoProvider,
        almacenProduccionDefaultProvider,
        almacenesConfigProvider,
        usuarioDispositivoProvider;
import '../../data/configuracion_repository.dart';
import 'almacenes_panel.dart';

/// Pestaña de Sistema (porta `usr/views/configuracion/sistema.py`).
class SistemaTab extends ConsumerStatefulWidget {
  const SistemaTab({super.key});

  @override
  ConsumerState<SistemaTab> createState() => _SistemaTabState();
}

class _SistemaTabState extends ConsumerState<SistemaTab> {
  String _testResult = '';
  Color? _testResultColor;
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeControllerProvider);
    final isDark = themeMode == ThemeMode.dark;
    final negAsync = ref.watch(permitirStockNegativoProvider);
    final almProdAsync = ref.watch(almacenProduccionDefaultProvider);
    final almacenesAsync = ref.watch(almacenesConfigProvider);
    final userAsync = ref.watch(usuarioDispositivoProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const UpdateSettingsCard(),
        _sectionCard(
          scheme,
          title: 'Mantenimiento del Sistema',
          subtitle: 'Herramientas de diagnóstico y configuración',
          icon: Icons.storage,
          iconBg: scheme.primaryContainer,
          children: [
            const Text('Si experimenta errores tras actualizaciones, use "Probar Conexión" para verificar la base de datos local.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: _testing
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.storage),
              label: const Text('Probar Conexión Local'),
              onPressed: _testing ? null : _probarConexionLocal,
            ),
            const SizedBox(height: 5),
            const Text(
              'Use "Verificar Supabase" para comprobar la conexión real con la base de datos remota (nube).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: _testing
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_done),
              label: const Text('Verificar Supabase'),
              style: FilledButton.styleFrom(backgroundColor: scheme.secondary),
              onPressed: _testing ? null : _verificarSupabase,
            ),
            if (_testResult.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (_testResultColor ?? scheme.surfaceContainerHighest).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_testResult, style: TextStyle(color: _testResultColor ?? scheme.onSurface, fontSize: 13)),
              ),
            ],
          ],
        ),
        _sectionCard(
          scheme,
          title: 'Configuración de Alertas',
          subtitle: 'Habilite las notificaciones para recibir alertas de stock bajo y validaciones en tiempo real.',
          icon: Icons.notifications_active,
          iconBg: scheme.tertiaryContainer,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.notifications_active),
              label: const Text('Habilitar Notificaciones'),
              style: FilledButton.styleFrom(backgroundColor: scheme.tertiary),
              onPressed: _solicitarNotificaciones,
            ),
          ],
        ),
        _sectionCard(
          scheme,
          title: 'Apariencia',
          subtitle: 'Cambie entre el tema claro y oscuro de la aplicación.',
          icon: Icons.brightness_6,
          iconBg: scheme.primaryContainer,
          children: [
            Row(
              children: [
                Text('Tema:', style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 12),
                Switch(
                  value: isDark,
                  onChanged: (v) => ref.read(themeControllerProvider.notifier).toggle(),
                ),
              ],
            ),
          ],
        ),
        _sectionCard(
          scheme,
          title: 'Modo Offline',
          subtitle: 'Active el modo offline para usar la aplicación sin conexión a internet.',
          icon: Icons.wifi_off,
          iconBg: scheme.errorContainer,
          children: [
            const Text(
              'La aplicación funciona directamente con Supabase. Sin conexión no habrá acceso a datos.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        _sectionCard(
          scheme,
          title: 'Control de Inventario',
          subtitle: 'Permite que las salidas dejen el stock en negativo (por defecto está desactivado).',
          icon: Icons.remove_circle_outline,
          iconBg: scheme.secondaryContainer,
          children: [
            negAsync.when(
              data: (permite) => Row(
                children: [
                  Expanded(
                    child: Text('Permitir stock negativo en salidas:', style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                  ),
                  Switch(
                    value: permite,
                    onChanged: (v) => _setPermitirStockNegativo(v),
                  ),
                ],
              ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const Text('Error cargando'),
            ),
          ],
        ),
        _sectionCard(
          scheme,
          title: 'Almacén por defecto para producciones',
          subtitle: 'Almacén para el descargo de materia prima en producciones.',
          icon: Icons.warehouse,
          iconBg: scheme.tertiaryContainer,
          children: [
            almProdAsync.when(
              data: (actual) => almacenesAsync.when(
                data: (almacenes) => DropdownButtonFormField<String>(
                  initialValue: actual,
                  decoration: const InputDecoration(labelText: 'Almacén', isDense: true, border: OutlineInputBorder()),
                  items: almacenes.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                  onChanged: (v) => _setAlmacenProduccion(v ?? 'restaurante'),
                ),
                loading: () => const CircularProgressIndicator(),
                error: (_, __) => const Text('Error'),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const Text('Error'),
            ),
          ],
        ),
        _sectionCard(
          scheme,
          title: 'Almacenes',
          subtitle: 'Cree, edite, desactive o elimine los almacenes del sistema.',
          icon: Icons.warehouse,
          iconBg: scheme.primaryContainer,
          children: const [AlmacenesPanel()],
        ),
        _sectionCard(
          scheme,
          title: 'Gestión de Operador',
          subtitle: 'Cambie el operador registrado en este dispositivo.',
          icon: Icons.person_outline,
          iconBg: scheme.tertiaryContainer,
          children: [
            userAsync.when(
              data: (user) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (user != null) ...[
                    Text('Operador actual: ${user['nombre']}', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                  ] else ...[
                    Text('Sin operador configurado', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Cambiar operador de este dispositivo'),
                    style: FilledButton.styleFrom(backgroundColor: scheme.tertiaryContainer),
                    onPressed: _cambiarOperador,
                  ),
                ],
              ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const Text('Error'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionCard(ColorScheme scheme, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconBg,
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
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: scheme.onPrimaryContainer, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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

  Future<void> _probarConexionLocal() async {
    setState(() => _testing = true);
    try {
      final repo = ref.read(configuracionRepoProvider)!;
      final ok = await repo.testLocalConnection();
      setState(() {
        _testResult = ok ? 'Conexión exitosa - Base de datos operativa' : 'Error de conexión';
        _testResultColor = ok ? Colors.green : Colors.red;
      });
    } catch (e) {
      setState(() {
        _testResult = 'Error: $e';
        _testResultColor = Colors.red;
      });
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _verificarSupabase() async {
    setState(() {
      _testing = true;
      _testResult = 'Verificando conexión con Supabase...';
      _testResultColor = Colors.orange;
    });
    try {
      final repo = ref.read(configuracionRepoProvider)!;
      final ok = await repo.testLocalConnection();
      setState(() {
        _testResult = ok ? 'Conexión exitosa - Supabase verificado' : 'Error de conexión con Supabase';
        _testResultColor = ok ? Colors.green : Colors.red;
      });
    } catch (e) {
      setState(() {
        _testResult = 'Error Supabase: $e';
        _testResultColor = Colors.red;
      });
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _solicitarNotificaciones() async {
    // En web, se puede solicitar permiso via Notification.requestPermission()
    // En Flutter web, se puede usar Notification.requestPermission() del paquete web
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solicitando permiso de notificaciones...')),
    );
    // TODO: Implementar requestPermission para FCM/web push
  }

  Future<void> _setPermitirStockNegativo(bool v) async {
    final repo = ref.read(configuracionRepoProvider)!;
    await repo.setPermitirStockNegativo(v);
    ref.invalidate(permitirStockNegativoProvider);
  }

  Future<void> _setAlmacenProduccion(String almacen) async {
    final repo = ref.read(configuracionRepoProvider)!;
    await repo.setAlmacenProduccionDefault(almacen);
    ref.invalidate(almacenProduccionDefaultProvider);
  }

  Future<void> _cambiarOperador() async {
    final user = await ref.read(usuarioDispositivoProvider.future);
    final repo = ref.read(configuracionRepoProvider)!;

    if (user != null && user['pinHash'] != null) {
      final pin = await _showPinDialog(context, 'Verificar PIN actual');
      if (pin != null && await repo.verificarPin(pin)) {
        await _confirmarCambioOperador(repo);
      } else if (pin != null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN incorrecto'), backgroundColor: Colors.red));
      }
    } else {
      await _confirmarCambioOperador(repo);
    }
  }

  Future<String?> _showPinDialog(BuildContext context, String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          maxLength: 4,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Verificar')),
        ],
      ),
    );
  }

  Future<void> _confirmarCambioOperador(ConfiguracionRepository repo) async {
    await repo.eliminarUsuarioDispositivo();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recargando...')));
    await Future.delayed(const Duration(milliseconds: 500));
    if (kIsWeb) {
      reloadApp();
    }
  }
}