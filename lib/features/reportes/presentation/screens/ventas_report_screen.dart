import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  bool _cargando = false;

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
      body: Column(
        children: [
          _buildFiltros(scheme),
          const Divider(height: 1),
          Expanded(
            child: _buildContenido(scheme),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          _buildDatePicker('Desde', _desde, (d) => setState(() => _desde = d)),
          _buildDatePicker('Hasta', _hasta, (d) => setState(() => _hasta = d)),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              value: _cajero,
              decoration: const InputDecoration(
                labelText: 'Cajero',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                DropdownMenuItem(value: 'Cajero 1', child: Text('Cajero 1')),
                DropdownMenuItem(value: 'Cajero 2', child: Text('Cajero 2')),
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
      ),
    );
  }

  Widget _buildDatePicker(String label, DateTime value, ValueChanged<DateTime> onChanged) {
    return SizedBox(
      width: 160,
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

    final total = _ventas.fold<double>(0, (sum, v) => sum + ((v['total'] as num?)?.toDouble() ?? 0));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: scheme.surfaceContainerHighest,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ResumenCard(label: 'Total Ventas', valor: '\$${total.toStringAsFixed(2)}', icon: Icons.attach_money, color: Colors.green),
              _ResumenCard(label: 'Comandas', valor: _ventas.length.toString(), icon: Icons.receipt_long, color: Colors.blue),
              _ResumenCard(label: 'Ticket Prom.', valor: _ventas.isNotEmpty ? '\$${(total / _ventas.length).toStringAsFixed(2)}' : '\$0.00', icon: Icons.analytics, color: Colors.orange),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _ventas.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final v = _ventas[index];
              final fecha = (v['fecha'] as String?)?.substring(0, 16) ?? '—';
              final cajero = v['cajero'] as String? ?? '—';
              final formaPago = v['forma_pago'] as String? ?? '—';
              final totalV = (v['total'] as num?)?.toDouble() ?? 0;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Text('${index + 1}', style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12)),
                ),
                title: Text('Venta #${v['id']} · $fecha'),
                subtitle: Text('$cajero · $formaPago'),
                trailing: Text('\$${totalV.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary, fontSize: 16)),
                onTap: () => _verDetalle(v),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _verDetalle(Map<String, dynamic> venta) async {
    try {
      final repo = ref.read(reportesRepoProvider);
      final items = await repo.getItemsVenta(venta['id'] as int);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Detalle Venta #${venta['id']}'),
          content: SizedBox(
            width: 400,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final it = items[i];
                return ListTile(
                  title: Text(it['nombre'] as String? ?? 'Producto #${it['producto_id']}'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
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
        Text(valor, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}