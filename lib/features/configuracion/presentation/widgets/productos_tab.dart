import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/categoria.dart';
import '../../../../core/models/producto.dart';
import '../../data/configuracion_providers.dart'
    show
        configuracionRepoProvider,
        categoriasConfigProvider,
        almacenesConfigProvider,
        productosConfigProvider;
import '../dialogs/producto_dialog.dart';

/// Pestaña de Productos (porta `usr/views/configuracion/productos.py`).
class ProductosTab extends ConsumerStatefulWidget {
  const ProductosTab({super.key});

  @override
  ConsumerState<ProductosTab> createState() => _ProductosTabState();
}

class _ProductosTabState extends ConsumerState<ProductosTab> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  int? _categoriaId;
  String? _almacen;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final productosAsync = ref.watch(productosConfigProvider);
    final categoriasAsync = ref.watch(categoriasConfigProvider);
    final almacenesAsync = ref.watch(almacenesConfigProvider);

    return Column(
      children: [
        _buildHeader(scheme, categoriasAsync, almacenesAsync),
        Expanded(
          child: productosAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e', style: TextStyle(color: scheme.error))),
            data: (productos) {
              final catPorId = <int, Categoria>{
                for (final c in categoriasAsync.value ?? <Categoria>[]) c.id: c,
              };
              final filtered = productos.where((Producto p) {
                if (_search.isNotEmpty && !p.nombre.toLowerCase().contains(_search.toLowerCase())) return false;
                if (_categoriaId != null && p.categoriaId != _categoriaId) return false;
                if (_almacen != null && p.almacenPredeterminado != _almacen) return false;
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    _search.isEmpty ? 'No hay productos' : 'Sin coincidencias',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final p = filtered[i];
                  final cat = p.categoriaId != null ? catPorId[p.categoriaId] : null;
                  return _ProductoItemCard(
                    producto: p,
                    categoria: cat,
                    scheme: scheme,
                    onEdit: () => _abrirDialogo(p),
                    onDelete: () => _eliminar(p),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ColorScheme scheme, AsyncValue<List<Categoria>> catAsync, AsyncValue<List<String>> almAsync) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar productos...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo'),
                onPressed: () => _abrirDialogo(null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: catAsync.when(
                  data: (cats) => DropdownButtonFormField<int?>(
                    initialValue: _categoriaId,
                    decoration: const InputDecoration(labelText: 'Categoría', isDense: true, border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Todas')),
                      for (final c in cats)
                        DropdownMenuItem(
                            value: c.id,
                            child: Text(c.activo
                                ? c.nombre
                                : '${c.nombre} (inactiva)')),
                    ],
                    onChanged: (v) => setState(() => _categoriaId = v),
                  ),
                  loading: () => DropdownButtonFormField<int?>(
                    items: const [], onChanged: null, decoration: const InputDecoration(labelText: 'Categoría', isDense: true),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: almAsync.when(
                  data: (alms) => DropdownButtonFormField<String?>(
                    initialValue: _almacen,
                    decoration: const InputDecoration(labelText: 'Almacén', isDense: true, border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                      for (final a in alms) DropdownMenuItem(value: a, child: Text(a)),
                    ],
                    onChanged: (v) => setState(() => _almacen = v),
                  ),
                  loading: () => DropdownButtonFormField<String?>(
                    items: const [], onChanged: null, decoration: const InputDecoration(labelText: 'Almacén', isDense: true),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _abrirDialogo(Producto? prod) async {
    final result = await showProductoDialog(context, ref.read(configuracionRepoProvider)!, producto: prod);
    if (result == true && mounted) {
      ref.invalidate(productosConfigProvider);
      ref.invalidate(categoriasConfigProvider);
    }
  }

  Future<void> _eliminar(Producto prod) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Eliminar "${prod.nombre}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final repo = ref.read(configuracionRepoProvider)!;
      await repo.deleteProducto(prod.id);
      if (mounted) ref.invalidate(productosConfigProvider);
    }
  }
}

class _ProductoItemCard extends StatelessWidget {
  const _ProductoItemCard({
    required this.producto,
    required this.categoria,
    required this.scheme,
    required this.onEdit,
    required this.onDelete,
  });

  final Producto producto;
  final Categoria? categoria;
  final ColorScheme scheme;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    final esPesable = p.esPesable;
    final catNombre = categoria == null
        ? 'N/A'
        : (categoria!.activo
            ? categoria!.nombre
            : '${categoria!.nombre} (inactiva)');
    final sku = p.codigo?.trim().isNotEmpty == true ? p.codigo!.trim() : 'Sin SKU';
    final tipoTxt = p.tipo.isEmpty ? 'ninguno' : p.tipo;
    final tipoTxtL = tipoTxt.toLowerCase();

    Color tipoColor;
    if (tipoTxtL == 'feria') {
      tipoColor = scheme.tertiary;
    } else if (tipoTxtL.contains('producci')) {
      tipoColor = scheme.error;
    } else if (tipoTxtL.contains('venta')) {
      tipoColor = Colors.green;
    } else {
      tipoColor = scheme.secondary;
    }

    final skuChips = <Widget>[
      if (!p.activo) _chip(scheme.error, Colors.white, 'INACTIVO'),
      _chip(scheme.primaryContainer, scheme.onPrimaryContainer, sku),
      _chip(tipoColor, Colors.white, tipoTxt.toUpperCase()),
      _chip(scheme.secondaryContainer, scheme.onSecondaryContainer, p.almacenPredeterminado.toUpperCase()),
      if (esPesable) _chip(scheme.tertiary, Colors.white, 'PESABLE'),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: esquemaCategoria(categoria),
              child: Icon(esPesable ? Icons.scale : Icons.inventory, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cat: $catNombre · Stock: ${p.stockActual.toStringAsFixed(esPesable ? 3 : 0)} ${p.unidadMedida}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 4, runSpacing: 4, children: skuChips),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit_outlined, color: scheme.primary),
              tooltip: 'Editar',
              onPressed: onEdit,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: scheme.error),
              tooltip: 'Eliminar',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(Color bg, Color fg, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Color esquemaCategoria(Categoria? cat) {
    final color = cat?.color;
    if (color != null && color.isNotEmpty) {
      final v = int.tryParse(color.replaceFirst('#', '0xFF'));
      if (v != null) return Color(v);
    }
    return scheme.primary;
  }
}
