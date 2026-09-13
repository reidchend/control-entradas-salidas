import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/activos_categoria.dart';
import '../data/activos_providers.dart';
import '../data/activos_repository.dart';
import 'dialogs/activo_dialog.dart';
import 'dialogs/activos_categoria_dialog.dart';
import 'dialogs/activos_excel_dialog.dart';
import 'dialogs/activos_filtro_dialog.dart';
import 'widgets/activos_categorias_grid.dart';
import 'widgets/activos_filtrados_panel.dart';
import 'widgets/activos_panel.dart';

/// Pantalla de Inventario de Activos (estilo InventarioScreen de productos):
/// - Raíz: grid de categorías.
/// - Click en una categoría → panel de activos de esa categoría con back.
/// - Se pueden crear categorías nuevas y activos dentro de cada categoría.
class ActivosScreen extends ConsumerStatefulWidget {
  const ActivosScreen({super.key});

  @override
  ConsumerState<ActivosScreen> createState() => _ActivosScreenState();
}

class _ActivosScreenState extends ConsumerState<ActivosScreen> {
  ActivosCategoria? _categoria;
  ActivosFiltro? _filtro;
  String _search = '';
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(activosRepoProvider)!;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: _categoria == null
          ? FloatingActionButton.extended(
              onPressed: () => _crearActivo(repo),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo activo'),
            )
          : null,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onScreenKey,
        child: Column(
          children: [
            _buildHeader(repo, colors),
            Expanded(child: _buildCuerpo(repo, colors)),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onScreenKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.f1) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildCuerpo(ActivosRepository repo, ColorScheme colors) {
    final filtro = _filtro;
    if (filtro != null) {
      return ActivosFiltradosPanel(
        repo: repo,
        filtro: filtro,
        onLimpiar: () => setState(() {
          _filtro = null;
          _search = '';
          _searchCtrl.clear();
        }),
      );
    }
    if (_categoria != null) {
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
                Expanded(
                  child: Text(
                    _categoria!.nombre,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ActivosPanel(
              repo: repo,
              categoria: _categoria!,
              searchTerm: _search,
            ),
          ),
        ],
      );
    }
    return ActivosCategoriasGrid(
      repo: repo,
      onSelect: (c) => setState(() {
        _categoria = c;
        _search = '';
        _searchCtrl.clear();
      }),
      onCreate: () => _crearCategoria(repo),
    );
  }

  Widget _buildHeader(ActivosRepository repo, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                hintText: _categoria != null
                    ? 'Buscar en ${_categoria!.nombre}...'
                    : 'Buscar activo... (F1)',
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
          if (_categoria == null && _filtro == null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.filter_alt_outlined),
              tooltip: 'Filtrar activos',
              onPressed: () => _abrirFiltro(repo),
            ),
          ],
          if (_categoria == null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Exportar a Excel',
              onPressed: () => showActivosExcelDialog(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _abrirFiltro(ActivosRepository repo) async {
    final filtro = await showActivosFiltroDialog(context, repo,
        actual: _filtro);
    if (filtro == null) return;
    setState(() {
      _filtro = filtro.vacio ? null : filtro;
      _search = '';
      _searchCtrl.clear();
    });
  }

  Future<void> _crearActivo(ActivosRepository repo) async {
    final categorias = await repo.getCategorias();
    final grupos = await repo.getGrupos();
    if (!mounted) return;
    final nuevo = await showActivoDialog(
        context, categorias: categorias, grupos: grupos);
    if (nuevo == null) return;
    try {
      await repo.createActivo(nuevo);
      if (mounted) setState(() {});
    } catch (e) {
      _snack('Error al crear activo: $e');
    }
  }

  Future<void> _crearCategoria(ActivosRepository repo) async {
    final nueva = await showActivosCategoriaDialog(context);
    if (nueva == null) return;
    try {
      final id = await repo.createCategoria(nueva.nombre, color: nueva.color);
      setState(() {});
      if (mounted) {
        // Entra directo a la categoría recién creada.
        _categoria = ActivosCategoria(
          id: id,
          nombre: nueva.nombre,
          color: nueva.color,
        );
      }
    } catch (e) {
      _snack('Error al crear categoría: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }
}