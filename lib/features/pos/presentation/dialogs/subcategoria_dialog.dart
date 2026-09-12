import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/categoria.dart';
import '../../../../core/models/pos_models.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../data/pos_providers.dart';

/// Alta/edición de sub-categoría (platos_categorias) con padre opcional
/// (categoría de inventario INV_ o categoría POS POS_).
/// Port de `ConfigPOSView._show_subcategoria_dialog` / `_show_subcat_edit_dialog`.
/// Retorna `true` si se guardó.
Future<bool> showSubcategoriaDialog(BuildContext context,
    {PosPlatoCategoria? subcategoria}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _SubcategoriaDialog(subcategoria: subcategoria),
  );
  return ok ?? false;
}

class _SubcategoriaDialog extends ConsumerStatefulWidget {
  const _SubcategoriaDialog({this.subcategoria});

  final PosPlatoCategoria? subcategoria;

  @override
  ConsumerState<_SubcategoriaDialog> createState() =>
      _SubcategoriaDialogState();
}

class _SubcategoriaDialogState extends ConsumerState<_SubcategoriaDialog> {
  static const _colores = [
    ('#FF6F00', 'Naranja'),
    ('#E53935', 'Rojo'),
    ('#43A047', 'Verde'),
    ('#1E88E5', 'Azul'),
    ('#8E24AA', 'Morado'),
    ('#00ACC1', 'Cyan'),
  ];

  final _nombreCtrl = TextEditingController();
  late String _color;
  String? _padre; // '' = sin padre, 'INV_x' | 'POS_x'
  bool _cargando = true;
  bool _guardando = false;

  List<Categoria> _catsInv = [];
  List<PosCategoria> _posCats = [];

  bool get _esEdicion => widget.subcategoria != null;

  @override
  void initState() {
    super.initState();
    final sc = widget.subcategoria;
    _nombreCtrl.text = sc?.nombre ?? '';
    _color = sc?.color ?? '#FF6F00';
    if (sc != null) {
      if (sc.categoriaPadreId != null) {
        _padre = 'INV_${sc.categoriaPadreId}';
      } else if (sc.posCategoriaPadreId != null) {
        _padre = 'POS_${sc.posCategoriaPadreId}';
      } else {
        _padre = '';
      }
    } else {
      _padre = null;
    }
    _cargarPadres();
  }

  Future<void> _cargarPadres() async {
    final repo = ref.read(posRepoProvider)!;
    final inv = await repo.getCategoriasPos();
    final pos = await repo.getPosCategorias();
    if (!mounted) return;
    setState(() {
      _catsInv = inv;
      _posCats = pos;
      _cargando = false;
    });
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese el nombre')),
      );
      return;
    }
    int? catPadreId;
    int? posPadreId;
    final padre = _padre ?? '';
    if (padre.startsWith('INV_')) {
      catPadreId = int.tryParse(padre.substring(4));
    } else if (padre.startsWith('POS_')) {
      posPadreId = int.tryParse(padre.substring(4));
    }
    setState(() => _guardando = true);
    final repo = ref.read(posRepoProvider)!;
    try {
      await repo.guardarPlatoCategoria(
        nombre,
        id: widget.subcategoria?.id,
        color: _color,
        activo: widget.subcategoria?.activo ?? true,
        categoriaPadreId: catPadreId,
        posCategoriaPadreId: posPadreId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar sub-categoría' : 'Nueva sub-categoría'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nombreCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _color,
                          decoration: const InputDecoration(
                            labelText: 'Color',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final c in _colores)
                              DropdownMenuItem(
                                value: c.$1,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: _hex(c.$1),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(c.$2),
                                  ],
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _color = v ?? _color),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _padre,
                    decoration: const InputDecoration(
                      labelText: 'Categoría padre (vacío = sin padre)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      if (_esEdicion)
                        const DropdownMenuItem(value: null, child: Text('Sin padre')),
                      for (final c in _catsInv)
                        DropdownMenuItem(
                          value: 'INV_${c.id}',
                          child: Text('INV: ${c.nombre}'),
                        ),
                      for (final c in _posCats)
                        DropdownMenuItem(
                          value: 'POS_${c.id}',
                          child: Text('POS: ${c.nombre}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _padre = v),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando || _cargando ? null : _guardar,
          child: Text(_guardando ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}

Color _hex(String value) {
  final v = value.replaceFirst('#', '');
  return Color(int.parse('FF$v', radix: 16));
}
