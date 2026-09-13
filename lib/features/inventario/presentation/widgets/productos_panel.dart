import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:control_entradas_salidas/core/models/producto.dart';
import 'package:control_entradas_salidas/features/inventario/data/inventario_repository.dart';
import 'package:control_entradas_salidas/features/inventario/data/inventario_providers.dart';
import '../dialogs/movimiento_dialog.dart';
import 'producto_card.dart';

/// Panel derecho: productos filtrados por categoría o búsqueda.
class ProductosPanel extends ConsumerStatefulWidget {
  const ProductosPanel({
    super.key,
    required this.repo,
    required this.categoriaId,
    required this.searchTerm,
  });

  final InventarioRepository repo;
  final int? categoriaId;
  final String searchTerm;

  @override
  ProductosPanelState createState() => ProductosPanelState();
}

class ProductosPanelState extends ConsumerState<ProductosPanel> {
  int _selectedIndex = 0;
  List<Producto>? _prods;
  final _listaFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  Future<List<Producto>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadProductos();
  }

  Future<List<Producto>> _loadProductos() async {
    if (widget.categoriaId != null) {
      return widget.repo.getProductosByCategoria(widget.categoriaId!);
    }
    return widget.repo.getAllProductos(searchTerm: widget.searchTerm);
  }

  @override
  void didUpdateWidget(ProductosPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchTerm != widget.searchTerm ||
        oldWidget.categoriaId != widget.categoriaId) {
      _selectedIndex = 0;
      _future = _loadProductos();
    }
  }

  /// Recarga la lista de productos (p. ej. tras un descargo de consumibles).
  void recargar() {
    setState(() => _future = _loadProductos());
  }

  @override
  void dispose() {
    _listaFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Navega la selección y lleva el foco a la lista (para Enter).
  void navegarSeleccion(int delta) {
    _navegar(delta);
    _listaFocus.requestFocus();
  }

  /// Abre el modal de movimiento del producto seleccionado.
  void abrirSeleccion() {
    final prods = _prods;
    if (prods == null || prods.isEmpty) return;
    final i = _selectedIndex.clamp(0, prods.length - 1);
    _showMovimientoDialog(prods[i]);
  }

  void _navegar(int delta) {
    final prods = _prods;
    if (prods == null || prods.isEmpty) return;
    final nuevo = (_selectedIndex + delta).clamp(0, prods.length - 1);
    if (nuevo == _selectedIndex) return;
    setState(() => _selectedIndex = nuevo);
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        (nuevo * 80 - _scrollCtrl.position.viewportDimension / 2)
            .clamp(0.0, _scrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final lk = event.logicalKey;
    if (lk == LogicalKeyboardKey.arrowDown) {
      _navegar(1);
      return KeyEventResult.handled;
    }
    if (lk == LogicalKeyboardKey.arrowUp) {
      _navegar(-1);
      return KeyEventResult.handled;
    }
    if (lk == LogicalKeyboardKey.enter ||
        lk == LogicalKeyboardKey.numpadEnter) {
      abrirSeleccion();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: FutureBuilder<List<Producto>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              var prods = snap.data ?? [];
              if (widget.searchTerm.isNotEmpty) {
                final q = widget.searchTerm.toLowerCase();
                prods = prods
                    .where((p) => p.nombre.toLowerCase().contains(q))
                    .toList();
              }
              _prods = prods;
              if (prods.isEmpty) {
                return const Center(child: Text('Sin productos'));
              }
              if (_selectedIndex >= prods.length) {
                _selectedIndex = prods.length - 1;
              }
              return Focus(
                focusNode: _listaFocus,
                onKeyEvent: _onListKey,
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: prods.length,
                  itemBuilder: (context, i) => ProductoCard(
                    producto: prods[i],
                    seleccionado: i == _selectedIndex,
                    onMovimiento: _showMovimientoDialog,
                    onToggleLista: _toggleListaCompra,
                    onCorregir: _showCorreccionDialog,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showMovimientoDialog(Producto p) async {
    await showMovimientoDialog(context, ref, p);
  }

  Future<void> _toggleListaCompra(Producto p) async {
    final repo = ref.read(inventarioRepoProvider);
    if (repo == null) return;
    await repo.toggleComprasLista(p.id);
    _future = _loadProductos();
    setState(() {});
  }

  Future<void> _showCorreccionDialog(Producto p) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Corregir ${p.nombre} - pendiente')),
    );
  }
}