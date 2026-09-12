import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_models.dart';
import '../../../../core/models/producto.dart' as domain;
import '../../../../core/utils/modal_sizing.dart';
import '../../../../features/inventario/data/inventario_providers.dart';
import '../../data/pos_providers.dart';

/// Alta/edición de plato con ingredientes dinámicos (port de
/// `ConfigPOSView._show_plato_dialog`). Retorna `true` si se guardó.
Future<bool> showPlatoConfigDialog(BuildContext context, {PosPlato? plato}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _PlatoConfigDialog(plato: plato),
  );
  return ok ?? false;
}

class _IngRow {
  _IngRow({this.productoId, String? cantidad, String? unidad}) {
    cantidadCtrl = TextEditingController(text: cantidad ?? '');
    unidadCtrl = TextEditingController(text: unidad ?? 'unidad');
  }

  int? productoId;
  late TextEditingController cantidadCtrl;
  late TextEditingController unidadCtrl;

  void dispose() {
    cantidadCtrl.dispose();
    unidadCtrl.dispose();
  }
}

class _PlatoConfigDialog extends ConsumerStatefulWidget {
  const _PlatoConfigDialog({this.plato});

  final PosPlato? plato;

  @override
  ConsumerState<_PlatoConfigDialog> createState() => _PlatoConfigDialogState();
}

class _PlatoConfigDialogState extends ConsumerState<_PlatoConfigDialog> {
  final _nombreCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _ingRows = <_IngRow>[];
  int? _categoriaId;
  bool _esContorno = false;
  bool _llevaContornos = false;
  bool _cargando = true;
  bool _guardando = false;

  List<PosPlatoCategoria> _categorias = [];
  List<domain.Producto> _insumos = [];

  bool get _esEdicion => widget.plato != null;

  @override
  void initState() {
    super.initState();
    final p = widget.plato;
    _nombreCtrl.text = p?.nombre ?? '';
    _precioCtrl.text = p == null ? '' : p.precioVenta.toStringAsFixed(2);
    _categoriaId = p?.categoriaId;
    _esContorno = p?.esContorno ?? false;
    _llevaContornos = p?.llevaContornos ?? false;
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final posRepo = ref.read(posRepoProvider)!;
    final invRepo = ref.read(inventarioRepoProvider)!;
    final cats = await posRepo.getPlatosCategorias();
    final productos = await invRepo.getAllProductos();
    final insumos = [
      for (final pr in productos)
        if (pr.tipo == 'Productos para uso interno' || pr.tipo == 'Insumos') pr,
    ];
    if (_esEdicion) {
      final ings = await posRepo.getIngredientes(widget.plato!.id);
      for (final i in ings) {
        _ingRows.add(_IngRow(
          productoId: i.productoId,
          cantidad: i.cantidad.toString(),
          unidad: i.unidad,
        ));
      }
    }
    if (!mounted) return;
    setState(() {
      _categorias = cats;
      _insumos = insumos;
      _cargando = false;
    });
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _precioCtrl.dispose();
    for (final r in _ingRows) {
      r.dispose();
    }
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
    if (_categoriaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione una categoría')),
      );
      return;
    }
    final ingredientes = <({int productoId, double cantidad, String unidad})>[];
    for (final r in _ingRows) {
      final pid = r.productoId;
      final cant = double.tryParse(r.cantidadCtrl.text.trim());
      if (pid != null && cant != null) {
        ingredientes.add((
          productoId: pid,
          cantidad: cant,
          unidad: r.unidadCtrl.text.trim().isEmpty
              ? 'unidad'
              : r.unidadCtrl.text.trim(),
        ));
      }
    }
    setState(() => _guardando = true);
    final repo = ref.read(posRepoProvider)!;
    try {
      if (_esEdicion) {
        await repo.actualizarPlato(
          widget.plato!.id,
          nombre: nombre,
          categoriaId: _categoriaId,
          precioVenta: double.tryParse(_precioCtrl.text.trim()) ?? 0,
          esContorno: _esContorno,
          llevaContornos: _llevaContornos,
          ingredientes: ingredientes,
        );
      } else {
        await repo.crearPlato(
          nombre,
          categoriaId: _categoriaId!,
          precioVenta: double.tryParse(_precioCtrl.text.trim()) ?? 0,
          esContorno: _esContorno,
          llevaContornos: _llevaContornos,
          ingredientes: ingredientes,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    }
  }

  Widget _ingredientesSection() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'INGREDIENTES (productos de inventario)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < _ingRows.length; i++) ...[
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _ingRows[i].productoId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Producto',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final p in _insumos)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text(p.nombre, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _ingRows[i].productoId = v),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _ingRows[i].cantidadCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Cantidad',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _ingRows[i].unidadCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Unidad',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Quitar',
                onPressed: () => setState(() {
                  _ingRows[i].dispose();
                  _ingRows.removeAt(i);
                }),
                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF5350)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (_ingRows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Sin ingredientes (opcional)',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ),
        TextButton.icon(
          onPressed: () => setState(() => _ingRows.add(_IngRow())),
          icon: const Icon(Icons.add, size: 18, color: Color(0xFF4CAF50)),
          label: const Text('Agregar ingrediente',
              style: TextStyle(color: Color(0xFF4CAF50))),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar PosPlato' : 'Nuevo PosPlato'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: _cargando
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
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
                    DropdownButtonFormField<int>(
                      initialValue: _categoriaId,
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in _categorias)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.nombre),
                          ),
                      ],
                      onChanged: (v) => setState(() => _categoriaId = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _precioCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Precio de venta (\$)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Es un contorno (acompañante)'),
                      value: _esContorno,
                      onChanged: (v) => setState(() => _esContorno = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Lleva contornos (elige al vender)'),
                      value: _llevaContornos,
                      onChanged: (v) => setState(() => _llevaContornos = v),
                    ),
                    const Divider(height: 24),
                    _ingredientesSection(),
                  ],
                ),
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
