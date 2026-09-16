import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/categoria.dart';
import '../../../core/models/existencia.dart';
import '../../../core/models/producto.dart';
import '../data/stock_providers.dart';
import '../data/stock_repository.dart';
import 'widgets/stock_stat_card.dart';
import 'widgets/productos_grid.dart';
import 'dialogs/historial_dialog.dart';
import 'dialogs/existencias_dialog.dart';

/// Pantalla de Stock / Toma de inventario (porta `usr/views/stock_view.py`).
/// Cabecera de estadisticas (total/bajo/agotado) + filtros + grid de
/// productos con historial, existencias y ajuste de conteo fisico.
///
/// Carga: contiene datos y los refresca en background. Durante una recarga
/// (poll o cambio de filtro) conserva los datos previos en pantalla para
/// evitar el parpadeo, y solo pinta el primer spinner cuando no hay nada.
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

  StockStats _stats = const StockStats();
  List<Producto> _productos = [];
  Map<int, List<Existencia>> _existencias = {};
  bool _cargando = false;
  bool _statsCargados = false;
  bool _cargandoMas = false;
  bool _hasMore = true;
  static const int _pageSize = 50;
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _cargarFiltros();
    _reload();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      // Saltar el refresco si hay una carga incremental en vuelo para no
      // pisar la lista que se está extendiendo.
      if (mounted && !_cargandoMas) _reload();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollCtrl.dispose();
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

  /// Recarga en background: conserva los datos actuales mientras consulta,
  /// de modo que no hay parpadeo al refrescar (poll periódico o filtros).
  void _reload() {
    final repo = ref.read(stockRepoProvider);
    if (repo == null) return;
    _cargar(repo);
  }

  Future<void> _cargar(StockRepository repo, {bool reset = true}) async {
    if (_statsCargados == false) {
      setState(() => _cargando = true);
    }
    try {
      final stats = await repo.getStockStats(almacen: _almacen);
      // En refrescos sin reset (poll) se recarga hasta lo que ya se ve para
      // conservar el scroll; en reset (filtros) se vuelve a la primera página.
      final volver = reset ? _pageSize : _productos.length + _pageSize;
      final productos = await repo.filterProductos(
        search: _search,
        categoriaId: _categoriaId,
        almacen: _almacen,
        stockStatus: _stockStatus,
        limit: volver,
      );
      final ids = [for (final p in productos) p.id];
      final exis = await repo.getExistenciasDeProductos(ids);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _statsCargados = true;
        _productos = productos;
        _existencias = exis;
        _cargando = false;
        _cargandoMas = false;
        _hasMore = productos.length >= volver;
      });
    } catch (e, st) {
      debugPrint('Error cargando stock: $e\n$st');
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Carga la siguiente página de productos (scroll infinito) y la agrega
  /// a la lista actual sin perder lo ya visible.
  Future<void> _cargarMas() async {
    if (_cargandoMas || !_hasMore) return;
    final repo = ref.read(stockRepoProvider);
    if (repo == null) return;
    setState(() => _cargandoMas = true);
    try {
      final offset = _productos.length;
      final nuevos = await repo.filterProductos(
        search: _search,
        categoriaId: _categoriaId,
        almacen: _almacen,
        stockStatus: _stockStatus,
        limit: _pageSize,
        offset: offset,
      );
      final exis = await repo.getExistenciasDeProductos(
          [for (final p in nuevos) p.id]);
      if (!mounted) return;
      setState(() {
        _productos = [..._productos, ...nuevos];
        _existencias = {..._existencias, ...exis};
        _cargandoMas = false;
        _hasMore = nuevos.length == _pageSize;
      });
    } catch (e, st) {
      debugPrint('Error cargando más stock: $e\n$st');
      if (mounted) setState(() => _cargandoMas = false);
    }
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
    final cargando = _cargando && !_statsCargados;
    final stats = _stats;

    String v(int n) => _statsCargados ? '$n' : (cargando ? '...' : '');
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
              _irAlInicio();
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
              _irAlInicio();
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
              _irAlInicio();
              _reload();
            },
          ),
        ],
      ),
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
              _irAlInicio();
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
              _irAlInicio();
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
              _irAlInicio();
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

  void _irAlInicio() {
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
  }

  Widget _buildLista() {
    if (_cargando && _productos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ProductosGrid(
      productos: _productos,
      existencias: _existencias,
      categorias: _categoriasMap,
      almacen: _almacen,
      scrollController: _scrollCtrl,
      onLoadMore: _cargarMas,
      hasMore: _hasMore,
      cargandoMas: _cargandoMas,
      onAction: _onAction,
    );
  }
}

extension _StringCapitalize on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}