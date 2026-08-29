import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reportes_repository.dart';

/// Pantalla de estadísticas y KPIs.
class EstadisticasReportScreen extends ConsumerStatefulWidget {
  const EstadisticasReportScreen({super.key});

  @override
  ConsumerState<EstadisticasReportScreen> createState() => _EstadisticasReportScreenState();
}

class _EstadisticasReportScreenState extends ConsumerState<EstadisticasReportScreen> {
  DateTime _desde = DateTime.now().subtract(const Duration(days: 30));
  DateTime _hasta = DateTime.now();
  Map<String, dynamic> _kpis = {};
  List<Map<String, dynamic>> _topProductos = [];
  List<Map<String, dynamic>> _tendencia = [];
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _actualizar();
  }

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
            onPressed: _cargando ? null : _actualizar,
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
          _buildTendenciaChart(scheme),
        ],
      ),
    );
  }

  Widget _buildKPIsGrid(ColorScheme scheme) {
    final kpis = [
      _KPIData('Ventas Totales', _fmtMoneda(_kpis['total_ventas'] ?? 0), Icons.attach_money, Colors.green),
      _KPIData('Ticket Promedio', _fmtMoneda(_kpis['ticket_promedio'] ?? 0), Icons.receipt_long, Colors.blue),
      _KPIData('Productos Vendidos', (_kpis['productos_vendidos'] ?? 0).toString(), Icons.inventory, Colors.orange),
      _KPIData('Comandas', (_kpis['num_comandas'] ?? 0).toString(), Icons.point_of_sale, Colors.purple),
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
    if (_topProductos.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text('Sin datos de productos', style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < _topProductos.length; i++)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text('${i + 1}', style: TextStyle(color: scheme.onPrimaryContainer)),
              ),
              title: Text(_topProductos[i]['nombre'] as String? ?? 'Producto #${_topProductos[i]['producto_id']}'),
              subtitle: Text('${(_topProductos[i]['cantidad'] as num?)?.toStringAsFixed(2) ?? '0'} unidades'),
              trailing: Text(
                _fmtMoneda((_topProductos[i]['total'] as num?)?.toDouble() ?? 0),
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

  Widget _buildTendenciaChart(ColorScheme scheme) {
    if (_tendencia.isEmpty) {
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
              Icon(Icons.show_chart_outlined, size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              Text(
                'Sin datos de tendencia para el período',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    // Encontrar min/max para escalar
    final valores = _tendencia.map((e) => (e['total'] as num?)?.toDouble() ?? 0).toList();
    final maxVal = valores.reduce((a, b) => a > b ? a : b);
    final minVal = valores.reduce((a, b) => a < b ? a : b);

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: CustomPaint(
        size: const Size(double.infinity, 180),
        painter: _TendenciaPainter(
          puntos: _tendencia
              .map((e) => (e['total'] as num?)?.toDouble() ?? 0)
              .toList(),
          maxVal: maxVal,
          minVal: minVal,
          color: scheme.primary,
        ),
      ),
    );
  }

  Future<void> _actualizar() async {
    setState(() => _cargando = true);
    try {
      final repo = ref.read(reportesRepoProvider);
      final kpis = await repo.getKPIs(desde: _desde, hasta: _hasta);
      final top = await repo.getTopProductos(desde: _desde, hasta: _hasta, limit: 10);
      final tendencia = await repo.getTendenciaVentas(desde: _desde, hasta: _hasta);
      if (mounted) {
        setState(() {
          _kpis = kpis;
          _topProductos = top;
          _tendencia = tendencia;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        _snack('Error: $e');
      }
    }
  }

  void _exportar() {
    _snack('Exportar reporte estadístico - pendiente');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String _fmtMoneda(double v) => '\$${v.toStringAsFixed(2)}';
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
                color: data.color.withValues(alpha: 0.15),
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

class _TendenciaPainter extends CustomPainter {
  final List<double> puntos;
  final double maxVal;
  final double minVal;
  final Color color;

  _TendenciaPainter({
    required this.puntos,
    required this.maxVal,
    required this.minVal,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (puntos.length < 2) return;

    final paintLine = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintArea = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final double range = maxVal - minVal;
    final double scale = range > 0 ? size.height * 0.8 / range : 0;
    final double baseY = size.height - (size.height * 0.1);

    final path = Path();
    final pathArea = Path();

    final double stepX = size.width / (puntos.length - 1);

    for (int i = 0; i < puntos.length; i++) {
      final double x = i * stepX;
      final double y = baseY - ((puntos[i] - minVal) * scale);

      if (i == 0) {
        path.moveTo(x, y);
        pathArea.moveTo(x, size.height);
        pathArea.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        pathArea.lineTo(x, y);
      }
    }

    // Cerrar área
    pathArea.lineTo(size.width, size.height);
    pathArea.lineTo(0, size.height);
    pathArea.close();

    canvas.drawPath(pathArea, paintArea);
    canvas.drawPath(path, paintLine);

    // Puntos
    final paintDot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < puntos.length; i++) {
      final double x = i * stepX;
      final double y = baseY - ((puntos[i] - minVal) * scale);
      canvas.drawCircle(Offset(x, y), 4, paintDot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}