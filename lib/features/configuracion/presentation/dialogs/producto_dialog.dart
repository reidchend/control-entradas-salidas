import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/producto.dart';
import '../../data/configuracion_repository.dart';
import '../../data/configuracion_providers.dart'
    show categoriasConfigProvider, almacenesConfigProvider;

/// Diálogo para crear/editar un Producto (porta `show_producto_dialog`).
Future<bool?> showProductoDialog(
  BuildContext context,
  ConfiguracionRepository repo, {
  Producto? producto,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _ProductoDialog(repo: repo, producto: producto),
  );
}

class _ProductoDialog extends ConsumerStatefulWidget {
  const _ProductoDialog({required this.repo, this.producto});

  final ConfiguracionRepository repo;
  final Producto? producto;

  @override
  ConsumerState<_ProductoDialog> createState() => _ProductoDialogState();
}

class _ProductoDialogState extends ConsumerState<_ProductoDialog> {
  final _nombreCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _pesoUnitarioCtrl = TextEditingController();
  final _precioVentaCtrl = TextEditingController();
  final _stockActualCtrl = TextEditingController();
  final _stockMinimoCtrl = TextEditingController();
  final _unidadCtrl = TextEditingController();

  int? _categoriaId;
  bool _esPesable = false;
  bool _requiereFotoPeso = false;
  String _tipo = 'ninguno';
  String _almacenPredeterminado = 'principal';
  bool _activo = true;
  bool _guardando = false;
  String? _codigoAuto;

  bool get _angosto => MediaQuery.of(context).size.width < 600;

  @override
  void initState() {
    super.initState();
    _unidadCtrl.text = 'unidad';
    _cargarCodigoAuto();
    if (widget.producto != null) {
      final p = widget.producto!;
      _nombreCtrl.text = p.nombre;
      _codigoCtrl.text = p.codigo ?? '';
      _descripcionCtrl.text = p.descripcion ?? '';
      _categoriaId = p.categoriaId;
      _esPesable = p.esPesable;
      _requiereFotoPeso = p.requiereFotoPeso;
      _pesoUnitarioCtrl.text = p.pesoUnitario?.toStringAsFixed(3) ?? '';
      _precioVentaCtrl.text = p.precioVenta.toStringAsFixed(2);
      _unidadCtrl.text = p.unidadMedida;
      _stockActualCtrl.text =
          p.stockActual.toStringAsFixed(_esPesable ? 3 : 0);
      _stockMinimoCtrl.text =
          p.stockMinimo.toStringAsFixed(_esPesable ? 3 : 0);
      _tipo = p.tipo;
      _almacenPredeterminado = p.almacenPredeterminado;
      _activo = p.activo;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _codigoCtrl.dispose();
    _descripcionCtrl.dispose();
    _pesoUnitarioCtrl.dispose();
    _precioVentaCtrl.dispose();
    _stockActualCtrl.dispose();
    _stockMinimoCtrl.dispose();
    _unidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCodigoAuto() async {
    if (widget.producto != null) return;
    final codigo = await widget.repo.proximoCodigoProducto();
    if (!mounted) return;
    setState(() => _codigoAuto = codigo);
    _codigoCtrl.text = codigo;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final esEdicion = widget.producto != null;
    final categoriasAsync = ref.watch(categoriasConfigProvider);
    final almacenesAsync = ref.watch(almacenesConfigProvider);

    return AlertDialog(
      title: Text(esEdicion ? 'Editar Producto' : 'Nuevo Producto'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
        child: SingleChildScrollView(
          child: categoriasAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Error: $e', style: TextStyle(color: scheme.error))),
            data: (categorias) {
              return almacenesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                    child:
                        Text('Error: $e', style: TextStyle(color: scheme.error))),
                data: (almacenes) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _nombreCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Nombre *',
                            border: OutlineInputBorder(),
                            isDense: true),
                        autofocus: true,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _codigoCtrl,
                        readOnly: !esEdicion,
                        decoration: InputDecoration(
                          labelText: 'Código',
                          helperText: esEdicion
                              ? null
                              : (_codigoAuto == null ? 'Auto...' : 'Auto'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descripcionCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Descripción',
                            border: OutlineInputBorder(),
                            isDense: true),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        initialValue: _categoriaId,
                        decoration: const InputDecoration(
                            labelText: 'Categoría',
                            border: OutlineInputBorder(),
                            isDense: true),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('Sin categoría')),
                          for (final c in categorias)
                            DropdownMenuItem(
                                value: c.id, child: Text(c.nombre)),
                        ],
                        onChanged: (v) => setState(() => _categoriaId = v),
                      ),
                      const SizedBox(height: 12),
                      if (_angosto)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SwitchListTile(
                              title: const Text('Pesable'),
                              value: _esPesable,
                              onChanged: (v) =>
                                  setState(() => _esPesable = v),
                              dense: true,
                            ),
                            SwitchListTile(
                              title: const Text('Requiere foto peso'),
                              value: _requiereFotoPeso,
                              onChanged: (v) =>
                                  setState(() => _requiereFotoPeso = v),
                              dense: true,
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: SwitchListTile(
                                title: const Text('Pesable'),
                                value: _esPesable,
                                onChanged: (v) =>
                                    setState(() => _esPesable = v),
                                dense: true,
                              ),
                            ),
                            Expanded(
                              child: SwitchListTile(
                                title: const Text('Requiere foto peso'),
                                value: _requiereFotoPeso,
                                onChanged: (v) =>
                                    setState(() => _requiereFotoPeso = v),
                                dense: true,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pesoUnitarioCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Peso unitario (kg)',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              enabled: _esPesable,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _precioVentaCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Precio venta',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _unidadCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Unidad *',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _tipo,
                              decoration: const InputDecoration(
                                  labelText: 'Tipo',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                              items: const [
                                DropdownMenuItem(
                                    value: 'ninguno',
                                    child: Text('Ninguno')),
                                DropdownMenuItem(
                                    value: 'feria', child: Text('Feria')),
                                DropdownMenuItem(
                                    value: 'producción',
                                    child: Text('Producción')),
                                DropdownMenuItem(
                                    value: 'productos para uso Interno',
                                    child: Text(
                                        'Productos para uso Interno')),
                                DropdownMenuItem(
                                    value: 'Productos para la venta',
                                    child:
                                        Text('Productos para la venta')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _tipo = v ?? 'ninguno'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _almacenPredeterminado,
                        decoration: const InputDecoration(
                            labelText: 'Almacén predeterminado',
                            border: OutlineInputBorder(),
                            isDense: true),
                        items: almacenes
                            .map((a) => DropdownMenuItem(
                                value: a, child: Text(a)))
                            .toList(),
                        onChanged: (v) => setState(
                            () => _almacenPredeterminado = v ?? 'principal'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _stockActualCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Stock actual',
                            border: OutlineInputBorder(),
                            isDense: true),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _stockMinimoCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Stock mínimo',
                            border: OutlineInputBorder(),
                            isDense: true),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Activo'),
                        value: _activo,
                        onChanged: (v) => setState(() => _activo = v),
                        dense: true,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _guardando ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed:
              _guardando || _nombreCtrl.text.trim().isEmpty ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) return;

    setState(() => _guardando = true);
    try {
      final data = <String, dynamic>{
        'nombre': nombre,
        'codigo':
            _codigoCtrl.text.trim().isEmpty ? null : _codigoCtrl.text.trim(),
        'descripcion': _descripcionCtrl.text.trim().isEmpty
            ? null
            : _descripcionCtrl.text.trim(),
        'categoria_id': _categoriaId,
        'es_pesable': _esPesable ? 1 : 0,
        'requiere_foto_peso': _requiereFotoPeso ? 1 : 0,
        'peso_unitario': _pesoUnitarioCtrl.text.isEmpty
            ? null
            : double.tryParse(_pesoUnitarioCtrl.text),
        'precio_venta':
            _precioVentaCtrl.text.isEmpty ? 0.0 : (double.tryParse(_precioVentaCtrl.text) ?? 0.0),
        'unidad_medida': _unidadCtrl.text.trim().isEmpty
            ? 'unidad'
            : _unidadCtrl.text.trim(),
        'stock_actual': double.tryParse(_stockActualCtrl.text) ?? 0,
        'stock_minimo': double.tryParse(_stockMinimoCtrl.text) ?? 0,
        'tipo': _tipo,
        'almacen_predeterminado': _almacenPredeterminado,
        'activo': _activo,
      };

      if (widget.producto != null) {
        await widget.repo.updateProducto(widget.producto!.id, data);
      } else {
        await widget.repo.createProducto(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }
}
