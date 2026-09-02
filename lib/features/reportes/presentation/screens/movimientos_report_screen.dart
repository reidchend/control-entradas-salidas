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
  void initState() {
    super.initState();
    // Normalizar a inicio/fin de día local para que el rango "de hoy" cubra
    // todo el día del usuario independientemente de la hora actual.
    final now = DateTime.now();
    _desde = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 7));
    _hasta = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

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
          _buildDatePicker('Desde', _desde, (d) => setState(() => _desde = DateTime(d.year, d.month, d.day))),
          _buildDatePicker('Hasta', _hasta, (d) => setState(() => _hasta = DateTime(d.year, d.month, d.day, 23, 59, 59))),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              value: _tipo,
              decoration: const InputDecoration(
                labelText: 'Tipo de movimiento',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                ..._tiposInfo.entries.map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value.$1))),
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
    for (final m in _movimientos) {
      final tipo = m['tipo'] as String? ?? '—';
      porTipo[tipo] = (porTipo[tipo] ?? 0) + 1;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          color: scheme.surfaceContainerHighest,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ResumenChip(
                  label: 'Total Movs.',
                  valor: _movimientos.length.toString(),
                  icon: Icons.inventory_2,
                  color: Colors.blue,
                ),
                const SizedBox(width: 12),
                ...porTipo.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _ResumenChip(
                    label: _tipoLabel(e.key),
                    valor: e.value.toString(),
                    icon: _iconoTipo(e.key),
                    color: _colorTipo(e.key),
                  ),
                )),
              ],
            ),
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
                title: Text('$prod · ${_tipoLabel(tipo)}'),
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

const Map<String, (String, Color, IconData)> _tiposInfo = {
  'entrada': ('Entrada', Colors.green, Icons.arrow_downward),
  'salida': ('Salida', Colors.red, Icons.arrow_upward),
  'ajuste': ('Ajuste', Colors.orange, Icons.tune),
  'tr_entrada': ('Tr. Entrada', Colors.blue, Icons.swap_horiz),
  'tr_salida': ('Tr. Salida', Colors.indigo, Icons.swap_horiz),
  'devolucion': ('Devolución', Colors.teal, Icons.replay),
  'venta': ('Venta', Colors.deepOrange, Icons.point_of_sale),
  'entrada_produccion': ('Ent. Producción', Colors.green, Icons.arrow_downward),
  'salida_produccion': ('Sal. Producción', Colors.red, Icons.arrow_upward),
  'consumo': ('Consumo', Colors.deepPurple, Icons.delete_sweep_outlined),
};

String _tipoLabel(String tipo) =>
    _tiposInfo[tipo]?.$1 ?? tipo.capitalize();

IconData _iconoTipo(String tipo) =>
    _tiposInfo[tipo]?.$3 ?? Icons.help;

Color _colorTipo(String tipo) =>
    _tiposInfo[tipo]?.$2 ?? Colors.grey;

class _ResumenChip extends StatelessWidget {
  const _ResumenChip({required this.label, required this.valor, required this.icon, required this.color});
  final String label;
  final String valor;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  valor,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}