import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.point_of_sale, size: 64, color: scheme.primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            'Reporte de Ventas',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Aquí se mostrarán las ventas filtradas\ncon totales, desglose por producto, etc.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Ver tabla de ventas'),
            onPressed: () => _snack('Implementar tabla con datos reales'),
          ),
        ],
      ),
    );
  }

  void _buscar() {
    _snack('Buscando ventas: $_desde - $_hasta | $_cajero | $_formaPago');
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