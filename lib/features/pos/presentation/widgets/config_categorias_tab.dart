import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_models.dart';
import '../../../../features/inventario/data/inventario_providers.dart';
import '../../data/pos_providers.dart';
import '../dialogs/pos_categoria_dialog.dart';
import '../dialogs/subcategoria_dialog.dart';
import 'categorias_rows.dart';

/// Pestaña de categorías POS + sub-categorías (port de `ConfigPOSView` sección
/// CATEGORÍAS POS): CRUD de pos_categorias y platos_categorias con toggle
/// de activo, todo sincronizado por outbox.
class ConfigCategoriasTab extends ConsumerStatefulWidget {
  const ConfigCategoriasTab({super.key});

  @override
  ConsumerState<ConfigCategoriasTab> createState() =>
      _ConfigCategoriasTabState();
}

class _ConfigCategoriasTabState extends ConsumerState<ConfigCategoriasTab> {
  List<PosCategoria> _posCats = [];
  List<PosPlatoCategoria> _subCats = [];
  Map<int, String> _invMap = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final repo = ref.read(posRepoProvider)!;
    final invRepo = ref.read(inventarioRepoProvider)!;
    final pos = await repo.getPosCategorias();
    final subs = await repo.getPlatosCategorias();
    final inv = await invRepo.getAllCategorias();
    if (!mounted) return;
    setState(() {
      _posCats = pos;
      _subCats = subs;
      _invMap = {for (final c in inv) c.id: c.nombre};
      _cargando = false;
    });
  }

  /// Categoría de platos raíz (sin padre): se lista como categoría y es la
  /// que aparece directamente en la raíz del POS.
  bool _esRaiz(PosPlatoCategoria c) =>
      c.categoriaPadreId == null &&
      c.posCategoriaPadreId == null &&
      c.platoCategoriaPadreId == null;

  String _labelSubcat(PosPlatoCategoria sc) {
    if (sc.categoriaPadreId != null) {
      return '${sc.nombre}  (en ${_invMap[sc.categoriaPadreId] ?? '?'})';
    }
    if (sc.posCategoriaPadreId != null) {
      final pos = _posCats
          .where((c) => c.id == sc.posCategoriaPadreId)
          .firstOrNull;
      return '${sc.nombre}  (en POS: ${pos?.nombre ?? '?'})';
    }
    if (sc.platoCategoriaPadreId != null) {
      final padre = _subCats
          .where((c) => c.id == sc.platoCategoriaPadreId)
          .firstOrNull;
      return '${sc.nombre}  (en PLATO: ${padre?.nombre ?? '?'})';
    }
    return sc.nombre;
  }

  Future<void> _nuevaPosCategoria() async {
    if (await showPosCategoriaDialog(context)) await _cargar();
  }

  Future<void> _editarPosCategoria(PosCategoria cat) async {
    if (await showPosCategoriaDialog(context, categoria: cat)) await _cargar();
  }

  Future<void> _eliminarPosCategoria(PosCategoria cat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar categoría POS'),
        content: Text("¿Eliminar '${cat.nombre}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(posRepoProvider)!.eliminarPosCategoria(cat.id);
    await _cargar();
  }

  Future<void> _toggleSubcat(PosPlatoCategoria sc, bool activo) async {
    await ref.read(posRepoProvider)!.guardarPlatoCategoria(
          sc.nombre,
          id: sc.id,
          color: sc.color,
          activo: activo,
          categoriaPadreId: sc.categoriaPadreId,
          posCategoriaPadreId: sc.posCategoriaPadreId,
          platoCategoriaPadreId: sc.platoCategoriaPadreId,
        );
    await _cargar();
  }

  Future<void> _eliminarSubcat(PosPlatoCategoria sc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar sub-categoría'),
        content: Text("¿Eliminar '${sc.nombre}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(posRepoProvider)!.eliminarPlatoCategoria(sc.id);
    await _cargar();
  }

  List<PosPlatoCategoria> get _catPlatos =>
      _subCats.where(_esRaiz).toList();

  List<PosPlatoCategoria> get _subcats =>
      _subCats.where((c) => !_esRaiz(c)).toList();

  Widget _subcatRow(PosPlatoCategoria sc) => SubcatRow(
        color: hexColor(sc.color),
        label: _labelSubcat(sc),
        activo: sc.activo,
        onToggle: (v) => _toggleSubcat(sc, v),
        onEdit: () async {
          if (await showSubcategoriaDialog(context, subcategoria: sc)) {
            await _cargar();
          }
        },
        onDelete: () => _eliminarSubcat(sc),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _nuevaPosCategoria,
                icon: const Icon(Icons.add),
                label: const Text('Nueva categoría POS'),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await showSubcategoriaDialog(context)) await _cargar();
                },
                icon: const Icon(Icons.subdirectory_arrow_right),
                label: const Text('Nueva categoría de platos'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : _posCats.isEmpty && _subCats.isEmpty
                  ? Center(
                      child: Text('Sin categorías POS',
                          style: TextStyle(color: scheme.outline)),
                    )
                  : ListView(
                      children: [
                        if (_posCats.isNotEmpty) ...[
                          const CatSectionLabel('Categorías POS'),
                          for (final c in _posCats)
                            PosCatRow(
                              color: hexColor(c.color),
                              nombre: c.nombre,
                              onEdit: () => _editarPosCategoria(c),
                              onDelete: () => _eliminarPosCategoria(c),
                            ),
                        ],
                        if (_catPlatos.isNotEmpty) ...[
                          const CatSectionLabel('Categorías de platos'),
                          for (final sc in _catPlatos) _subcatRow(sc),
                        ],
                        if (_subcats.isNotEmpty) ...[
                          const CatSectionLabel('Sub-categorías'),
                          for (final sc in _subcats) _subcatRow(sc),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }
}

