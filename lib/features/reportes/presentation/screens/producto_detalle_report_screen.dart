import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/snackbar_utils.dart';
import '../../data/reportes_repository.dart';

/// Pantalla de reporte detallado por producto:
/// - Busca un producto (autocomplete)
/// - Muestra: ventas, entradas, salidas, traslados, ajustes
/// - Calcula frecuencia de entradas (cada cuántos días se compra/produce)
class ProductoDetalleReportScreen extends ConsumerStatefulWidget {
  const ProductoDetalleReportScreen({super.key});

  @override
  ConsumerState<ProductoDetalleReportScreen> createState() => _ProductoDetalleReportScreenState();
}

class _ProductoDetalleReportScreenState extends ConsumerState<ProductoDetalleReportScreen> {
  DateTime _desde = DateTime.now().subtract(const Duration(days: 30));
  DateTime _hasta = DateTime.now();
  Map<String, dynamic>? _productoSeleccionado;
  Map<String, dynamic> _detalle = {};
  bool _cargandoDetalle = false;
  String _filtroTipoMovimiento = 'Todos';

  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte por Producto'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_productoSeleccionado != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              tooltip: 'Limpiar producto',
              onPressed: () => setState(() {
                _productoSeleccionado = null;
                _detalle = {};
                _searchController.clear();
              }),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltros(scheme),
          const Divider(height: 1),
          if (_productoSeleccionado == null)
            _buildEmptyState(scheme)
          else
            Expanded(child: _cargandoDetalle
                ? const Center(child: CircularProgressIndicator())
                : _buildContenido(scheme)),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 600;
          if (esMovil) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDatePicker('Desde', _desde, (d) => setState(() => _desde = d)),
                const SizedBox(height: 12),
                _buildDatePicker('Hasta', _hasta, (d) => setState(() => _hasta = d)),
                const SizedBox(height: 12),
                _buildProductSearch(scheme),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Buscar'),
                  onPressed: _productoSeleccionado != null && !_cargandoDetalle
                      ? _cargarDetalle
                      : null,
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
                width: 300,
                child: _buildProductSearch(scheme),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Buscar'),
                onPressed: _productoSeleccionado != null && !_cargandoDetalle
                    ? _cargarDetalle
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProductSearch(ColorScheme scheme) {
    return Autocomplete<Map<String, dynamic>>(
      displayStringForOption: (p) => '${p['nombre']} (${p['codigo'] ?? 'sin código'})',
      optionsBuilder: (TextEditingValue textEditingValue) async {
        if (textEditingValue.text.length < 2) return <Map<String, dynamic>>[];
        try {
          final repo = ref.read(reportesRepoProvider);
          return await repo.buscarProductos(textEditingValue.text);
        } catch (_) {
          return <Map<String, dynamic>>[];
        }
      },
      onSelected: (producto) {
        setState(() {
          _productoSeleccionado = producto;
          _searchController.text = producto['nombre'] as String;
          _detalle = {};
        });
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Producto',
            hintText: 'Escribe 2+ letras para buscar...',
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: _productoSeleccionado != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      textEditingController.clear();
                      setState(() {
                        _productoSeleccionado = null;
                        _detalle = {};
                      });
                    },
                  )
                : const Icon(Icons.search, size: 18),
          ),
          onChanged: (v) {
            // Auto-limpia si borran el texto
            if (v.isEmpty && _productoSeleccionado != null) {
              setState(() {
                _productoSeleccionado = null;
                _detalle = {};
              });
            }
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final p = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(p['nombre'] as String),
                    subtitle: Text('${p['codigo'] ?? ''} · ${p['unidad_medida'] ?? ''}'),
                    onTap: () => onSelected(p),
                  );
                },
              ),
            ),
          ),
        );
      },
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

  Widget _buildEmptyState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_outlined, size: 80, color: scheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'Selecciona un producto',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Busca un producto y presiona "Buscar" para ver su historial completo:\nventas, entradas, salidas, traslados, ajustes y frecuencia de compras.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenido(ColorScheme scheme) {
    final ventas = _detalle['ventas'] as List<dynamic>? ?? [];
    final movimientos = _detalle['movimientos'] as List<dynamic>? ?? [];
    final frecuencia = _detalle['frecuencia_entradas_dias'] as double?;
    final totalEntradas = _detalle['total_entradas'] as int? ?? 0;

    if (ventas.isEmpty && movimientos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_outlined, size: 64, color: scheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Sin datos en el período', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('Ajusta las fechas e intenta de nuevo', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final totalVentas = ventas.fold<double>(0, (sum, v) => sum + ((v['subtotal'] as num?)?.toDouble() ?? 0));
    final totalCantVendida = ventas.fold<double>(0, (sum, v) => sum + ((v['cantidad'] as num?)?.toDouble() ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header del producto
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    radius: 28,
                    child: Icon(Icons.inventory, size: 28, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _productoSeleccionado!['nombre'] as String,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (_productoSeleccionado!['codigo'] != null)
                          Text('Código: ${_productoSeleccionado!['codigo']}', style: TextStyle(color: scheme.onSurfaceVariant)),
                        Text('${_productoSeleccionado!['unidad_medida'] ?? 'unidad'} · Stock mín: ${_productoSeleccionado!['stock_minimo'] ?? 0}',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Resumen KPIs
          _buildResumenKPIs(scheme, totalVentas, totalCantVendida, movimientos.length, frecuencia, totalEntradas),
          const SizedBox(height: 24),

          // Frecuencia de entradas
          if (frecuencia != null)
            _buildFrecuenciaCard(scheme, frecuencia, totalEntradas),
          if (frecuencia != null) const SizedBox(height: 16),

          // Tabs para cada tipo
          DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.primary,
                  tabs: const [
                    Tab(text: 'Ventas'),
                    Tab(text: 'Movimientos'),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 400,
                  child: TabBarView(
                    children: [
                      _buildVentasTab(scheme, ventas),
                      _buildMovimientosTab(scheme, movimientos),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenKPIs(ColorScheme scheme, double totalVentas, double totalCantVendida,
      int totalMovimientos, double? frecuencia, int totalEntradas) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 500 ? 2 : 1);
        final kpis = [
          _KPIData('Total Ventas', '\$${totalVentas.toStringAsFixed(2)}', Icons.attach_money, Colors.green),
          _KPIData('Cant. Vendida', totalCantVendida.toStringAsFixed(3), Icons.inventory, Colors.blue),
          _KPIData('Movimientos', totalMovimientos.toString(), Icons.swap_vert, Colors.orange),
          if (frecuencia != null)
            _KPIData('Frecuencia Entradas', '${frecuencia.toStringAsFixed(1)} días', Icons.schedule, Colors.teal),
        ];

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

  Widget _buildFrecuenciaCard(ColorScheme scheme, double frecuencia, int totalEntradas) {
    return Card(
      color: Colors.teal.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.schedule, size: 28, color: Colors.teal),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Frecuencia de Entradas',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Se realizan entradas cada ${frecuencia.toStringAsFixed(1)} días en promedio (${totalEntradas} entradas en el período).',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Útil para planificar compras/producción y evitar desabasto.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVentasTab(ColorScheme scheme, List<dynamic> ventas) {
    if (ventas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.point_of_sale, size: 64, color: scheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Sin ventas en el período', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: ventas.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final v = ventas[index] as Map<String, dynamic>;
        final fecha = _fmtFecha(v['created_at']);
        final cajero = v['cajero_nombre'] as String? ?? '—';
        final ubicacion = v['mesa_nombre'] != null
            ? 'Mesa ${v['mesa_nombre']}'
            : (v['habitacion_numero'] != null ? 'Hab. ${v['habitacion_numero']}' : '—');
        final cant = (v['cantidad'] as num?)?.toDouble() ?? 0;
        final subtotal = (v['subtotal'] as num?)?.toDouble() ?? 0;
        final correlativo = v['correlativo'] as int? ?? v['id'] as int? ?? 0;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green.withValues(alpha: 0.15),
            child: Icon(Icons.point_of_sale, color: Colors.green.shade700, size: 20),
          ),
          title: Text('Venta #$correlativo · $fecha'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$cajero · $ubicacion'),
              Text('${cant.toStringAsFixed(3)} ${_productoSeleccionado!['unidad_medida'] ?? 'unidad'} · \$${subtotal.toStringAsFixed(2)}'),
            ],
          ),
          trailing: Text('\$${subtotal.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: 16)),
        );
      },
    );
  }

  Widget _buildMovimientosTab(ColorScheme scheme, List<dynamic> movimientos) {
    if (movimientos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: scheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Sin movimientos en el período', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final tiposUnicos = <String>['Todos'];
    for (final m in movimientos) {
      final t = m['tipo'] as String? ?? '';
      if (t.isNotEmpty && !tiposUnicos.contains(t)) tiposUnicos.add(t);
    }

    final filtrados = _filtroTipoMovimiento == 'Todos'
        ? movimientos
        : movimientos.where((m) => (m['tipo'] as String? ?? '') == _filtroTipoMovimiento).toList();

    return Column(
      children: [
        // Filtro de tipo de movimiento
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: scheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.filter_list, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _filtroTipoMovimiento,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Filtrar por tipo',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: tiposUnicos.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t == 'Todos' ? 'Todos' : _tipoLabel(t)),
                  )).toList(),
                  onChanged: (v) => setState(() => _filtroTipoMovimiento = v ?? 'Todos'),
                ),
              ),
              const SizedBox(width: 8),
              Text('${filtrados.length} mov.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
        // Lista
        Expanded(
          child: filtrados.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.filter_alt_off, size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 8),
                      Text('Sin movimientos de tipo "$_filtroTipoMovimiento"', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: filtrados.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final m = filtrados[index] as Map<String, dynamic>;
        final fecha = _fmtFecha(m['fecha_movimiento']);
        final tipo = m['tipo'] as String? ?? '—';
        final cant = (m['cantidad'] as num?)?.toDouble() ?? 0;
        final almacen = m['almacen'] as String? ?? '—';
        final obs = ((m['observaciones'] as String?) ?? '').trim();
        final registradoPor = m['registrado_por'] as String? ?? '—';

        Color tipoColor;
        IconData tipoIcon;
        switch (tipo) {
          case 'entrada':
          case 'entrada_produccion':
            tipoColor = Colors.green;
            tipoIcon = Icons.arrow_downward;
            break;
          case 'salida':
          case 'salida_produccion':
            tipoColor = Colors.red;
            tipoIcon = Icons.arrow_upward;
            break;
          case 'devolucion_produccion':
            tipoColor = Colors.purple;
            tipoIcon = Icons.replay;
            break;
          case 'ajuste':
            tipoColor = Colors.orange;
            tipoIcon = Icons.tune;
            break;
          case 'tr_entrada':
            tipoColor = Colors.blue;
            tipoIcon = Icons.swap_horiz;
            break;
          case 'tr_salida':
            tipoColor = Colors.indigo;
            tipoIcon = Icons.swap_horiz;
            break;
          default:
            tipoColor = Colors.grey;
            tipoIcon = Icons.help;
        }

        String tipoLabel = tipo
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: tipoColor.withValues(alpha: 0.15),
            child: Icon(tipoIcon, color: tipoColor, size: 20),
          ),
          title: Text('$tipoLabel · $fecha'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$almacen · Por: $registradoPor'),
              if (obs.isNotEmpty) Text(obs, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
          trailing: Text(
            '${cant.toStringAsFixed(3)} ${m['unidad'] ?? ''}',
            style: TextStyle(fontWeight: FontWeight.bold, color: tipoColor, fontSize: 16),
          ),
        );
      },
    ),
    ),
  ],
);
  }

  Future<void> _cargarDetalle() async {
    if (_productoSeleccionado == null) return;
    setState(() => _cargandoDetalle = true);
    try {
      final repo = ref.read(reportesRepoProvider);
      final productoId = _productoSeleccionado!['id'] as int;
      _detalle = await repo.getProductoDetalle(
        productoId: productoId,
        desde: _desde,
        hasta: _hasta,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _cargandoDetalle = false);
    }
  }

  void _snack(String msg) {
    showErrorSnackBar(context, msg);
  }

  String _fmtFecha(dynamic v) {
    final dt = DateTime.tryParse(v?.toString() ?? '');
    if (dt == null) return '—';
    final l = dt.toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
  }

  String _tipoLabel(String tipo) => tipo
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
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