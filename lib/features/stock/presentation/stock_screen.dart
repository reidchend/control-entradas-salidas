import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/realtime_service.dart';
import '../../../core/data/supabase_providers.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/producto.dart';
import '../data/stock_providers.dart';
import '../data/stock_repository.dart';
import 'widgets/stock_stat_card.dart';
import 'widgets/productos_grid.dart';
import 'dialogs/historial_dialog.dart';
import 'dialogs/existencias_dialog.dart';

/// Pantalla de Stock / Toma de inventario (porta `usr/views/stock_view.py`).
/// Cabecera de estadísticas (total/bajo/agotado) + filtros + grid de
/// productos con historial, existencias y ajuste de conteo físico.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  String _search = '';
  int? _categoriaId;
  String? _almacen;
  String? _stockStatus;
  List<Categoria> _categorias = [];
  List<String> _almacenes = [];
  Map<int, String> _categoriasMap = {};
  Future<StockStats>? _statsFuture;
  Future<List<Producto>>? _productosFuture;
  final List<RealtimeSubscription> _rtSubs = [];

  @override
  void initState() {
    super.initState();
    _cargarFiltros();
    _reload();
    _initRealtime();
  }

  void _initRealtime() {
    final rt = ref.read(realtimeServiceProvider);
    if (rt == null) return;
    for (final table in ['existencias', 'movimientos']) {
      final sub = rt.subscribe(
        table: table,
        events: {PostgresChangeEvent.insert, PostgresChangeEvent.update, PostgresChangeEvent.delete},
      );
      sub.stream.listen((_) {
        if (mounted) _reload();
      });
      _rtSubs.add(sub);
    }
  }

  @override
  void dispose() {
    for (final sub in _rtSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _cargarFiltros() async {
    final repo = ref.read(stockRepoProvider)!;
    final cats = await repo.loadCategorias();
    final alm = await repo.getAlmacenes();
    if (mounted) {
      setState(() {
        _categorias = cats;
        _almacenes = alm;
        _categoriasMap = {for (final c in cats) c.id: c.nombre};
      });
    }
  }

  void _reload() {
    final repo = ref.read(stockRepoProvider)!;
    setState(() {
      _statsFuture = repo.getStockStats(almacen: _almacen);
      _productosFuture = repo.filterProductos(
        search: _search,
        categoriaId: _categoriaId,
        almacen: _almacen,
        stockStatus: _stockStatus,
      );
    });
  }

  void _onAction(String action, Producto p) {
    switch (action) {
      case 'historial':
        _verHistorial(p);
        break;
      case 'existencias':
        _verExistencias(p);
        break;
    }
  }

  Future<void> _verHistorial(Producto p) async {
    final repo = ref.read(stockRepoProvider)!;
    final movs = await repo.getProductoHistorial(p.id);
    if (!mounted) return;
    await showHistorialDialog(
      context,
      titulo: 'Historial: ${p.nombre}',
      movimientos: movs,
      esPesable: p.esPesable,
    );
  }

  Future<void> _verExistencias(Producto p) async {
    final repo = ref.read(stockRepoProvider)!;
    await showExistenciasDialog(context, ref, p, repo);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _buildStats(scheme),
        ),
        _buildFiltros(),
        const SizedBox(height: 8),
        Expanded(child: _buildLista()),
      ],
    );
  }

  Widget _buildStats(ColorScheme scheme) {
    return FutureBuilder<StockStats>(
      future: _statsFuture,
      builder: (context, snap) {
        final stats = snap.data ?? const StockStats();
        final cargando = snap.connectionState == ConnectionState.waiting;

        String v(int n) => cargando ? '...' : '$n';
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              StockStatCard(
                title: 'Total',
                value: v(stats.total),
                icon: Icons.inventory_2_outlined,
                color: Colors.blue,
                active: _stockStatus == null,
                onTap: () {
                  setState(() => _stockStatus = null);
                  _reload();
                },
              ),
              const SizedBox(width: 12),
              StockStatCard(
                title: 'Bajo Stock',
                value: v(stats.bajo),
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFFB8C00),
                active: _stockStatus == 'low',
                onTap: () {
                  setState(() => _stockStatus = 'low');
                  _reload();
                },
              ),
              const SizedBox(width: 12),
              StockStatCard(
                title: 'Agotado',
                value: v(stats.agotado),
                icon: Icons.error_outline,
                color: scheme.error,
                active: _stockStatus == 'out',
                onTap: () {
                  setState(() => _stockStatus = 'out');
                  _reload();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFiltros() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final busqueda = TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar producto...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            onChanged: (v) {
              _search = v;
              _reload();
            },
          );
          final cat = DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'Categoría',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            initialValue: _categoriaId?.toString(),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todas')),
              for (final c in _categorias)
                DropdownMenuItem(
                  value: c.id.toString(),
                  child: Text(c.nombre),
                ),
            ],
            onChanged: (v) {
              _categoriaId = v == null ? null : int.parse(v);
              _reload();
            },
          );
          final alm = DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'Almacén',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            initialValue: _almacen,
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos')),
              for (final a in _almacenes)
                DropdownMenuItem(value: a, child: Text(a.capitalize())),
            ],
            onChanged: (v) {
              _almacen = v;
              _reload();
            },
          );

          final esEscritorio = constraints.maxWidth >= 720;
          if (esEscritorio) {
            return Row(
              children: [
                Expanded(flex: 2, child: busqueda),
                const SizedBox(width: 12),
                Expanded(child: cat),
                const SizedBox(width: 12),
                Expanded(child: alm),
              ],
            );
          }
          return Column(
            children: [
              busqueda,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: cat),
                  const SizedBox(width: 12),
                  Expanded(child: alm),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLista() {
    return FutureBuilder<List<Producto>>(
      future: _productosFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final prods = snap.data ?? [];
        return ProductosGrid(
          productos: prods,
          categorias: _categoriasMap,
          almacen: _almacen,
          onAction: _onAction,
        );
      },
    );
  }
}

extension _StringCapitalize on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
