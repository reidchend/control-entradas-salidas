import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/categoria.dart';
import '../../data/configuracion_providers.dart';
import '../dialogs/categoria_dialog.dart';

class CategoriasTab extends ConsumerStatefulWidget {
  const CategoriasTab({super.key});

  @override
  ConsumerState<CategoriasTab> createState() => _CategoriasTabState();
}

class _CategoriasTabState extends ConsumerState<CategoriasTab> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categoriasAsync = ref.watch(categoriasConfigProvider);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar...',
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
                label: const Text('Nueva'),
                onPressed: () => _abrirDialogo(null),
              ),
            ],
          ),
        ),
        Expanded(
          child: categoriasAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e', style: TextStyle(color: scheme.error))),
            data: (categorias) {
              final filtered = categorias.where((c) {
                if (_search.isEmpty) return true;
                return c.nombre.toLowerCase().contains(_search.toLowerCase());
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    _search.isEmpty ? 'No hay categorías' : 'Sin coincidencias',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final c = filtered[i];
                  final estadoTxt = c.activo ? 'Activa' : 'Inactiva';
                  final estadoColor =
                      c.activo ? Colors.green : scheme.onSurfaceVariant;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: c.activo
                            ? _parseColor(c.color)
                            : scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.category,
                          color: c.activo
                              ? Colors.white
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (c.descripcion?.isNotEmpty == true)
                            Text(
                              c.descripcion!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                            ),
                          Text(
                            estadoTxt,
                            style: TextStyle(fontSize: 11, color: estadoColor),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit_outlined, color: scheme.primary),
                            tooltip: 'Editar',
                            onPressed: () => _abrirDialogo(c),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: scheme.error),
                            tooltip: 'Eliminar',
                            onPressed: () => _eliminar(c),
                          ),
                        ],
                      ),
                      onTap: () => _abrirDialogo(c),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _abrirDialogo(Categoria? cat) async {
    final result = await showCategoriaDialog(context, ref.read(configuracionRepoProvider)!, categoria: cat);
    if (result == true && mounted) {
      ref.invalidate(categoriasConfigProvider);
    }
  }

  Future<void> _eliminar(Categoria cat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Eliminar "${cat.nombre}"?'),
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
      await repo.deleteCategoria(cat.id);
      if (mounted) ref.invalidate(categoriasConfigProvider);
    }
  }

  Color _parseColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', '0xFF'));
    return v != null ? Color(v) : Colors.blue;
  }
}
