import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/snackbar_utils.dart';
import '../../data/reportes_repository.dart';

/// Pantalla de reporte de movimientos (entradas, salidas, ajustes, etc.)
class MovimientosReportScreen extends ConsumerStatefulWidget {
  const MovimientosReportScreen({super.key});

  @override
  ConsumerState<MovimientosReportScreen> createState() => _MovimientosReportScreenState();
}

class _MovimientosReportScreenState extends ConsumerState<MovimientosReportScreen> {
  DateTime _desde = DateTime.now().subtract(const Duration(days: 7));
  DateTime _hasta = DateTime.now();
  String _tipo = 'Todos';
  String _almacen = 'Todos';
  List<Map<String, dynamic>> _movimientos = [];
  bool _cargando = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte de Movimientos'),
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
              value: _tipo,
              decoration: const InputDecoration(
                labelText: 'Tipo de movimiento',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                DropdownMenuItem(value: 'entrada', child: Text('Entrada')),
                DropdownMenuItem(value: 'salida', child: Text('Salida')),
                DropdownMenuItem(value: 'ajuste', child: Text('Ajuste')),
                DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
                DropdownMenuItem(value: 'entrada_produccion', child: Text('Entrada Producción')),
                DropdownMenuItem(value: 'salida_produccion', child: Text('Salida Producción')),
              ],
              onChanged: (v) => setState(() => _tipo = v ?? 'Todos'),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              value: _almacen,
              decoration: const InputDecoration(
                labelText: 'Almacén',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                DropdownMenuItem(value: 'principal', child: Text('Principal')),
                DropdownMenuItem(value: 'restaurante', child: Text('Restaurante')),
                DropdownMenuItem(value: 'bodega', child: Text('Bodega')),
              ],
              onChanged: (v) => setState(() => _almacen = v ?? 'Todos'),
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
    if (_movimientos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: scheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Sin movimientos en el período', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('Ajusta los filtros e intenta de nuevo', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    // Resumen por tipo
    final Map<String, int> porTipo = {};
    final Map<String, double> cantidadPorTipo = {};
    for (final m in _movimientos) {
      final tipo = m['tipo'] as String? ?? '—';
      final cant = (m['cantidad'] as num?)?.toDouble() ?? 0;
      porTipo[tipo] = (porTipo[tipo] ?? 0) + 1;
      cantidadPorTipo[tipo] = (cantidadPorTipo[tipo] ?? 0) + cant;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: scheme.surfaceContainerHighest,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ResumenCard(label: 'Total Movs.', valor: _movimientos.length.toString(), icon: Icons.inventory_2, color: Colors.blue),
                  ...porTipo.entries.map((e) => _ResumenCard(
                    label: e.key.capitalize(),
                    valor: e.value.toString(),
                    icon: _iconoTipo(e.key),
                    color: _colorTipo(e.key),
                  )),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: cantidadPorTipo.entries.map((e) => _ResumenCard(
                  label: 'Cant. ${e.key.capitalize()}',
                  valor: e.value.toStringAsFixed(2),
                  icon: Icons.straighten,
                  color: _colorTipo(e.key),
                )).toList(),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _movimientos.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final m = _movimientos[index];
              final fecha = (m['fecha_movimiento'] as String?)?.substring(0, 16) ?? '—';
              final tipo = m['tipo'] as String? ?? '—';
              final prod = m['producto_nombre'] as String? ?? 'Producto #${m['producto_id']}';
              final cant = (m['cantidad'] as num?)?.toDouble() ?? 0;
              final almacen = m['almacen'] as String? ?? '—';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _colorTipo(tipo).withValues(alpha: 0.15),
                  child: Icon(_iconoTipo(tipo), color: _colorTipo(tipo), size: 20),
                ),
                title: Text('$prod · $tipo'),
                subtitle: Text('$fecha · $almacen'),
                trailing: Text(
                  '${cant.toStringAsFixed(3)} ${m['unidad'] ?? ''}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: _colorTipo(tipo), fontSize: 16),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _buscar() async {
    setState(() => _cargando = true);
    try {
      final repo = ref.read(reportesRepoProvider);
      final tipo = _tipo == 'Todos' ? null : _tipo;
      final almacen = _almacen == 'Todos' ? null : _almacen;
      _movimientos = await repo.getMovimientos(
        desde: _desde,
        hasta: _hasta,
        tipo: tipo,
        almacen: almacen,
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
}

extension _StringExt on String {
  String capitalize() => isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : this;
}

IconData _iconoTipo(String tipo) {
  switch (tipo) {
    case 'entrada':
    case 'entrada_produccion':
      return Icons.arrow_downward;
    case 'salida':
    case 'salida_produccion':
      return Icons.arrow_upward;
    case 'ajuste':
      return Icons.tune;
    case 'transferencia':
      return Icons.swap_horiz;
    default:
      return Icons.help;
  }
}

Color _colorTipo(String tipo) {
  switch (tipo) {
    case 'entrada':
    case 'entrada_produccion':
      return Colors.green;
    case 'salida':
    case 'salida_produccion':
      return Colors.red;
    case 'ajuste':
      return Colors.orange;
    case 'transferencia':
      return Colors.purple;
    default:
      return Colors.grey;
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
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}