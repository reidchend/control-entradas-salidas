import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_models.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../../pos/data/pos_providers.dart';
import '../../data/reportes_repository.dart';

/// Pantalla de reporte de ventas con filtros y resultados.
class VentasReportScreen extends ConsumerStatefulWidget {
  const VentasReportScreen({super.key});

  @override
  ConsumerState<VentasReportScreen> createState() => _VentasReportScreenState();
}

class _VentasReportScreenState extends ConsumerState<VentasReportScreen> {
  DateTime _desde = DateTime.now().subtract(const Duration(days: 7));
  DateTime _hasta = DateTime.now();
  String _cajero = 'Todos';
  String _formaPago = 'Todas';
  List<Map<String, dynamic>> _ventas = [];
  List<PosUsuario> _cajeros = [];
  bool _cargando = false;
  bool _cargandoCajeros = true;

  @override
  void initState() {
    super.initState();
    _cargarCajeros();
    _buscar();
  }

  Future<void> _cargarCajeros() async {
    setState(() => _cargandoCajeros = true);
    try {
      final repo = ref.read(posRepoProvider);
      if (repo != null) {
        final cajeros = await repo.getUsuarios();
        if (mounted) setState(() => _cajeros = cajeros);
      }
    } catch (e) {
      if (mounted) _snack('Error cargando cajeros: $e');
    } finally {
      if (mounted) setState(() => _cargandoCajeros = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte de Ventas'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Exportar',
            onPressed: _exportar,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 600;
          if (!esMovil) {
            return Column(
              children: [
                _buildFiltros(scheme),
                const Divider(height: 1),
                Expanded(child: _buildContenido(scheme)),
              ],
            );
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildFiltros(scheme)),
              const SliverToBoxAdapter(child: Divider(height: 1)),
              ..._buildContenidoSlivers(scheme),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFiltros(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 600;
          if (esMovil) {
            final cajeroField = _cargandoCajeros
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<String>(
                    value: _cajero,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Cajero',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                      ..._cajeros.map((c) =>
                          DropdownMenuItem(value: c.nombre, child: Text(c.nombre))),
                    ],
                    onChanged: (v) => setState(() => _cajero = v ?? 'Todos'),
                  );
            final formaPagoField = DropdownButtonFormField<String>(
              value: _formaPago,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Forma de pago',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Todas', child: Text('Todas')),
                DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                DropdownMenuItem(value: 'Tarjeta', child: Text('Tarjeta')),
                DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
              ],
              onChanged: (v) => setState(() => _formaPago = v ?? 'Todas'),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildDatePicker('Desde', _desde, (d) => setState(() => _desde = d), width: double.infinity),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDatePicker('Hasta', _hasta, (d) => setState(() => _hasta = d), width: double.infinity),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: cajeroField),
                    const SizedBox(width: 8),
                    Expanded(child: formaPagoField),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Buscar'),
                  onPressed: _buscar,
                ),
              ],
            );
          }
          return Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _buildDatePicker('Desde', _desde, (d) => setState(() => _desde = d)),
              _buildDatePicker('Hasta', _hasta, (d) => setState(() => _hasta = d)),
              SizedBox(
                width: 180,
                child: _cargandoCajeros
                    ? const Center(child: CircularProgressIndicator())
                    : DropdownButtonFormField<String>(
                        value: _cajero,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Cajero',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                          ..._cajeros.map((c) =>
                              DropdownMenuItem(value: c.nombre, child: Text(c.nombre))),
                        ],
                        onChanged: (v) => setState(() => _cajero = v ?? 'Todos'),
                      ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _formaPago,
                  decoration: const InputDecoration(
                    labelText: 'Forma de pago',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Todas', child: Text('Todas')),
                    DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'Tarjeta', child: Text('Tarjeta')),
                    DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
                  ],
                  onChanged: (v) => setState(() => _formaPago = v ?? 'Todas'),
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Buscar'),
                onPressed: _buscar,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDatePicker(String label, DateTime value, ValueChanged<DateTime> onChanged, {double? width}) {
    return SizedBox(
      width: width ?? 160,
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 1)),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
          ),
          child: Text('${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}'),
        ),
      ),
    );
  }

  Widget _buildContenido(ColorScheme scheme) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ventas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.point_of_sale, size: 64, color: scheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Sin ventas en el período', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('Ajusta los filtros e intenta de nuevo', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildResumen(scheme),
        Expanded(
          child: _buildLista(scheme),
        ),
      ],
    );
  }

  List<Widget> _buildContenidoSlivers(ColorScheme scheme) {
    if (_cargando) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_ventas.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.point_of_sale, size: 64, color: scheme.primary.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('Sin ventas en el período', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Text('Ajusta los filtros e intenta de nuevo', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(child: _buildResumen(scheme)),
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList.separated(
          itemCount: _ventas.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) => _buildItem(context, index, scheme),
        ),
      ),
    ];
  }

  Widget _buildResumen(ColorScheme scheme) {
    final total = _ventas.fold<double>(0, (sum, v) => sum + ((v['total'] as num?)?.toDouble() ?? 0));
    return Container(
      padding: const EdgeInsets.all(16),
      color: scheme.surfaceContainerHighest,
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 16,
        runSpacing: 16,
        children: [
          _ResumenCard(label: 'Total Ventas', valor: '\$${total.toStringAsFixed(2)}', icon: Icons.attach_money, color: Colors.green),
          _ResumenCard(label: 'Comandas', valor: _ventas.length.toString(), icon: Icons.receipt_long, color: Colors.blue),
          _ResumenCard(label: 'Ticket Prom.', valor: _ventas.isNotEmpty ? '\$${(total / _ventas.length).toStringAsFixed(2)}' : '\$0.00', icon: Icons.analytics, color: Colors.orange),
        ],
      ),
    );
  }

  Widget _buildLista(ColorScheme scheme) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _ventas.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildItem(context, index, scheme),
    );
  }

  Widget _buildItem(BuildContext context, int index, ColorScheme scheme) {
    final v = _ventas[index];
    final fecha = _fmtFecha(v['created_at']);
    final cajero = v['cajero_nombre'] as String? ?? v['usuario_id']?.toString() ?? '—';
    final formaPago = v['forma_pago'] as String? ?? '—';
    final totalV = (v['total'] as num?)?.toDouble() ?? 0;
    final correlativo = v['correlativo'] as int? ?? v['id'] as int? ?? 0;
    final mesaNombre = v['mesa_nombre'] as String?;
    final habitacionNumero = v['habitacion_numero'] as String?;

    String ubicacion = '';
    if (mesaNombre != null && mesaNombre.isNotEmpty) {
      ubicacion = 'Mesa: $mesaNombre';
    } else if (habitacionNumero != null && habitacionNumero.isNotEmpty) {
      ubicacion = 'Hab. $habitacionNumero';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text('${index + 1}', style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12)),
      ),
      title: Text('Venta #$correlativo · $fecha'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$cajero · $formaPago'),
          if (ubicacion.isNotEmpty)
            Text(ubicacion, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
      trailing: Text('\$${totalV.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary, fontSize: 16)),
      onTap: () => _verDetalle(v),
    );
  }

  Future<void> _verDetalle(Map<String, dynamic> venta) async {
    try {
      final repo = ref.read(reportesRepoProvider);
      final ventaId = (venta['id'] as num?)?.toInt() ?? 0;
      if (ventaId == 0) {
        _snack('Error: Venta sin ID válido');
        return;
      }
      final items = await repo.getItemsVenta(ventaId);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Detalle Venta #$ventaId'),
          content: SizedBox(
            width: modalContentWidth(context),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final it = items[i];
                final prodId = (it['producto_id'] as num?)?.toInt() ?? 0;
                return ListTile(
                  title: Text(it['nombre'] as String? ?? 'Producto #$prodId'),
                  subtitle: Text('${it['cantidad']} x \$${((it['precio'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
                  trailing: Text('\$${(((it['cantidad'] as num?)?.toDouble() ?? 0) * ((it['precio'] as num?)?.toDouble() ?? 0)).toStringAsFixed(2)}'),
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
        ),
      );
    } catch (e) {
      _snack('Error cargando detalle: $e');
    }
  }

  Future<void> _buscar() async {
    setState(() => _cargando = true);
    try {
      final repo = ref.read(reportesRepoProvider);
      final cajero = _cajero == 'Todos' ? null : _cajero;
      final formaPago = _formaPago == 'Todas' ? null : _formaPago;
      _ventas = await repo.getVentas(
        desde: _desde,
        hasta: _hasta,
        cajero: cajero,
        formaPago: formaPago,
      );
      if (mounted) setState(() {});
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _exportar() {
    _snack('Exportar a Excel/PDF - pendiente');
  }

  void _snack(String msg) {
    showErrorSnackBar(context, msg);
  }

  /// Formatea una fecha que puede venir como String ISO (proxy web) o como
  /// DateTime (driver nativo `package:postgres`) sin reventar el render.
  String _fmtFecha(dynamic v) {
    final dt = DateTime.tryParse(v?.toString() ?? '');
    if (dt == null) return '—';
    final l = dt.toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
  }
}

class _ResumenCard extends StatelessWidget {
  const _ResumenCard({required this.label, required this.valor, required this.icon, required this.color});
  final String label;
  final String valor;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(valor, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}