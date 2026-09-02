import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/categoria.dart';
import '../data/inventario_providers.dart';
import '../data/inventario_repository.dart';
import 'widgets/categorias_grid.dart';
import 'widgets/productos_panel.dart';
import 'widgets/lista_compra_panel.dart';
import 'dialogs/descargo_consumibles_dialog.dart';

/// Pantalla de Inventario (porta `usr/views/inventario_view.py`).
///
/// Flujo estilo Flet:
/// - Raíz: GridView de cards de categorías a pantalla completa.
/// - Click en una categoría → vista de productos de esa categoría con back.
/// - Lista de compra: panel con items agrupados por categoría.
class InventarioScreen extends ConsumerStatefulWidget {
  const InventarioScreen({super.key});

  @override
  ConsumerState<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends ConsumerState<InventarioScreen> {
  Categoria? _categoria;
  String _search = '';
  bool _vistaListaCompra = false;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _productosKey = GlobalKey<ProductosPanelState>();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(inventarioRepoProvider)!;
    final colors = Theme.of(context).colorScheme;

    final Widget cuerpo = _vistaListaCompra
        ? ListaCompraPanel(
            repo: repo,
            onClose: () => setState(() => _vistaListaCompra = false),
          )
            : _categoria != null
                ? _buildProductosDeCategoria(repo, colors)
                : CategoriasGrid(
                    repo: repo,
                    searchTerm: _search,
                    onSelect: (c) => setState(() {
                      _categoria = c;
                      _search = '';
                      _searchCtrl.clear();
                    }),
                  );

    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: _onScreenKey,
        child: Column(
          children: [
            _buildHeader(repo, colors),
            Expanded(child: cuerpo),
          ],
        ),
      ),
    );
  }

  /// F1 enfoca el buscador.
  KeyEventResult _onScreenKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final lk = event.logicalKey;

    if (lk == LogicalKeyboardKey.f1) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (lk == LogicalKeyboardKey.f2) {
      showDescargoConsumiblesDialog(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildProductosDeCategoria(InventarioRepository repo, ColorScheme colors) {
    final categoria = _categoria!;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Volver a categorías',
                onPressed: () => setState(() {
                  _categoria = null;
                  _search = '';
                  _searchCtrl.clear();
                }),
              ),
              CircleAvatar(
                radius: 12,
                backgroundColor: _parseColor(categoria.color),
                child: Text(
                  categoria.nombre.isNotEmpty ? categoria.nombre[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  categoria.nombre,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ProductosPanel(
            key: _productosKey,
            repo: repo,
            categoriaId: categoria.id,
            searchTerm: _search,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(InventarioRepository repo, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          if (!_vistaListaCompra) ...[
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                decoration: InputDecoration(
                  hintText: _categoria != null ? 'Buscar en ${_categoria!.nombre}...' : 'Buscar categoría...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colors.surfaceContainerHighest,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Descargo de consumibles (F2)',
              onPressed: () => showDescargoConsumiblesDialog(context),
            ),
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined),
              tooltip: 'Lista de compras',
              onPressed: () => setState(() => _vistaListaCompra = true),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _vistaListaCompra = false),
            ),
            const Text('Lista de Compras', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Enviar a WhatsApp',
              onPressed: () {
                // TODO: integrar WhatsApp
              },
            ),
          ],
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', '0xFF'));
    return v != null ? Color(v) : Colors.blue;
  }
}
