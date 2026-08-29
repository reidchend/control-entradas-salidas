import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pantalla de estadísticas y KPIs.
class EstadisticasReportScreen extends ConsumerStatefulWidget {
  const EstadisticasReportScreen({super.key});

  @override
  ConsumerState<EstadisticasReportScreen> createState() => _EstadisticasReportScreenState();
}

class _EstadisticasReportScreenState extends ConsumerState<EstadisticasReportScreen> {
  DateTime _desde = DateTime.now().subtract(const Duration(days: 30));
  DateTime _hasta = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas y KPIs'),
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
          FilledButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Actualizar KPIs'),
            onPressed: _actualizar,
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('KPIs Principales', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _buildKPIsGrid(scheme),
          const SizedBox(height: 32),
          Text('Top Productos', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _buildTopProductos(scheme),
          const SizedBox(height: 32),
          Text('Tendencia de Ventas', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _buildGraficoPlaceholder(scheme),
        ],
      ),
    );
  }

  Widget _buildKPIsGrid(ColorScheme scheme) {
    final kpis = [
      _KPIData('Ventas Totales', '\$12,450.00', Icons.attach_money, Colors.green),
      _KPIData('Ticket Promedio', '\$28.50', Icons.receipt_long, Colors.blue),
      _KPIData('Productos Vendidos', '1,234', Icons.inventory, Colors.orange),
      _KPIData('Comandas', '89', Icons.point_of_sale, Colors.purple),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 500 ? 2 : 1);
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.6,
          children: kpis.map((kpi) => _KPICard(data: kpi)).toList(),
        );
      },
    );
  }

  Widget _buildTopProductos(ColorScheme scheme) {
    final productos = [
      {'nombre': 'Hamburguesa Clásica', 'unidades': 156, 'total': '\$1,560.00'},
      {'nombre': 'Papas Fritas', 'unidades': 142, 'total': '\$710.00'},
      {'nombre': 'Gaseosa 500ml', 'unidades': 138, 'total': '\$690.00'},
      {'nombre': 'Helado Vainilla', 'unidades': 98, 'total': '\$490.00'},
      {'nombre': 'Ensalada César', 'unidades': 87, 'total': '\$1,305.00'},
    ];

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < productos.length; i++)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text('${i + 1}', style: TextStyle(color: scheme.onPrimaryContainer)),
              ),
              title: Text(productos[i]['nombre'] as String),
              subtitle: Text('${productos[i]['unidades']} unidades vendidas'),
              trailing: Text(
                productos[i]['total'] as String,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGraficoPlaceholder(ColorScheme scheme) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart_outlined, size: 48, color: scheme.onSurfaceVariant.withOpacity(0.5)),
            const SizedBox(height: 8),
            Text(
              'Gráfico de tendencia de ventas\n(pendiente implementar con fl_chart)',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  void _actualizar() {
    _snack('Actualizando KPIs para $_desde - $_hasta');
  }

  void _exportar() {
    _snack('Exportar reporte estadístico - pendiente');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}

class _KPIData {
  const _KPIData(this.titulo, this.valor, this.icono, this.color);
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;
}

class _KPICard extends StatelessWidget {
  const _KPICard({required this.data});
  final _KPIData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: data.color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(data.icono, size: 28, color: data.color),
            ),
            const SizedBox(height: 12),
            Text(
              data.valor,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: data.color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              data.titulo,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}