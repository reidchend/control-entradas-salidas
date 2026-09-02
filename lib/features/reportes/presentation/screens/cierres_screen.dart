import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_cierre_models.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../data/cierres_repository.dart';

/// Pantalla de historial de cierres de caja
class CierresHistorialScreen extends ConsumerStatefulWidget {
  const CierresHistorialScreen({super.key});

  @override
  ConsumerState<CierresHistorialScreen> createState() => _CierresHistorialScreenState();
}

class _CierresHistorialScreenState extends ConsumerState<CierresHistorialScreen> {
  DateTime? _desde;
  DateTime? _hasta;
  int? _usuarioId;
  List<CierreCaja> _cierres = [];
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _desde = DateTime.now().subtract(const Duration(days: 30));
    _hasta = DateTime.now();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final repo = ref.read(cierresRepoProvider);
      _cierres = await repo.getCierres(
        desde: _desde,
        hasta: _hasta,
        usuarioId: _usuarioId,
        limit: 100,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Cierres'),
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
            label: const Text('Actualizar'),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(String label, DateTime? value, ValueChanged<DateTime> onChanged) {
    return SizedBox(
      width: 160,
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
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
          child: Text(value != null
              ? '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}'
              : 'Seleccionar'),
        ),
      ),
    );
  }

  Widget _buildContenido(ColorScheme scheme) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cierres.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: scheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Sin cierres en el período', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('Ajusta los filtros e intenta de nuevo', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: scheme.surfaceContainerHighest,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 24,
            runSpacing: 12,
            children: [
              _ResumenCard(label: 'Total Cierres', valor: _cierres.length.toString(), icon: Icons.history, color: Colors.blue),
              _ResumenCard(label: 'Caja Inicial Total', valor: '\$${_totalInicial.toStringAsFixed(2)}', icon: Icons.attach_money, color: Colors.green),
              _ResumenCard(label: 'Ventas Totales', valor: '\$${_totalVentas.toStringAsFixed(2)}', icon: Icons.point_of_sale, color: Colors.orange),
              _ResumenCard(label: 'Caja Final Total', valor: '\$${_totalFinal.toStringAsFixed(2)}', icon: Icons.savings, color: Colors.purple),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _cierres.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final c = _cierres[index];
              final fecha = (c.cerradaEn as String?)?.substring(0, 16) ?? '—';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Text('${index + 1}', style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12)),
                ),
                title: Text('Cierre #${c.sesionId} · $fecha'),
                subtitle: Text('${c.usuarioNombre} · Duración: ${_duracionTexto(c)}'),
                trailing: Text('\$${c.cajaFinal.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary, fontSize: 16)),
                onTap: () => _verDetalle(c),
              );
            },
          ),
        ),
      ],
    );
  }

  double get _totalInicial => _cierres.fold(0.0, (s, c) => s + c.cajaInicial);
  double get _totalVentas => _cierres.fold(0.0, (s, c) => s + c.totalVentas);
  double get _totalFinal => _cierres.fold(0.0, (s, c) => s + c.cajaFinal);

  Future<void> _verDetalle(CierreCaja cierre) async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Detalle Cierre #${cierre.sesionId}'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetalleRow(label: 'Cajero', valor: cierre.usuarioNombre),
                _DetalleRow(label: 'Apertura', valor: _fmtFecha(cierre.abiertaEn)),
                _DetalleRow(label: 'Cierre', valor: _fmtFecha(cierre.cerradaEn)),
                _DetalleRow(label: 'Duración', valor: _duracionTexto(cierre)),
                const Divider(),
                _DetalleRow(label: 'Caja Inicial', valor: '\$${cierre.cajaInicial.toStringAsFixed(2)}', bold: true),
                _DetalleRow(label: 'Total Ventas', valor: '\$${cierre.totalVentas.toStringAsFixed(2)}'),
                _DetalleRow(label: 'Caja Final', valor: '\$${cierre.cajaFinal.toStringAsFixed(2)}', bold: true, color: Colors.green),
                const Divider(),
                Text('Reporte Simple:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildReporteSimple(cierre.reporteSimple),
                const SizedBox(height: 16),
                Text('Reporte Detallado:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildReporteDetallado(cierre.reporteDetallado),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  Widget _buildReporteSimple(ReporteSimple reporte) {
    final widgets = <Widget>[
      for (final l in reporte.lineas)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(l.nombre, style: const TextStyle(fontSize: 12))),
              Text('${l.cantidad.toStringAsFixed(3)} x \$${l.precioUnitario.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11)),
              Text('\$${l.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
    ];
    if (reporte.contornos.isNotEmpty) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(const Text('Contornos servidos:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)));
      for (final cn in reporte.contornos) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(cn.nombre, style: const TextStyle(fontSize: 11))),
                Text(cn.cantidad.toStringAsFixed(3), style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        );
      }
    }
    return Column(children: widgets);
  }

  Widget _buildReporteDetallado(ReporteDetallado reporte) {
    return Column(
      children: reporte.desgloses.map((d) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(d.ingrediente, style: const TextStyle(fontSize: 11))),
            Text('Cons: ${d.totalConsumido.toStringAsFixed(3)}', style: const TextStyle(fontSize: 10)),
            Text('Stock: ${d.stockFinal.toStringAsFixed(3)}', style: const TextStyle(fontSize: 10)),
          ],
        ),
      )).toList(),
    );
  }

  String _duracionTexto(CierreCaja cierre) {
    try {
      final a = DateTime.parse(cierre.abiertaEn);
      final c = DateTime.parse(cierre.cerradaEn);
      final d = c.difference(a);
      return '${d.inHours}h ${d.inMinutes % 60}m';
    } catch (_) {
      return '—';
    }
  }

  String _fmtFecha(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  void _exportar() {
    _snack('Exportar a Excel/PDF - pendiente');
  }

  void _snack(String msg) {
    showErrorSnackBar(context, msg);
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

class _DetalleRow extends StatelessWidget {
  const _DetalleRow({required this.label, required this.valor, this.bold = false, this.color});
  final String label;
  final String valor;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          const SizedBox(width: 12),
          Flexible(child: Text(valor, textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color))),
        ],
      ),
    );
  }
}