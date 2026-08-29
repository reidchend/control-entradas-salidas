import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/requisicion.dart';
import '../../data/requisiciones_providers.dart';
import '../../data/requisiciones_repository.dart';
import '../dialogs/buscador_productos_dialog.dart';
import '../dialogs/cantidad_dialog.dart';

class FormView extends ConsumerStatefulWidget {
  const FormView({
    super.key,
    required this.onBack,
    required this.onSaved,
    this.requisicion,
  });

  final VoidCallback onBack;
  final VoidCallback onSaved;
  final Requisicion? requisicion;

  @override
  ConsumerState<FormView> createState() => _FormViewState();
}

class _FormViewState extends ConsumerState<FormView> {
  List<RequisicionItem> _items = [];
  List<String> _almacenes = [];
  String? _origen;
  String? _destino;
  final _obsCtrl = TextEditingController();
  bool _guardando = false;
  bool _cargado = false;

  bool get _editando => widget.requisicion != null;

  @override
  void initState() {
    super.initState();
    _obsCtrl.text = widget.requisicion?.observaciones ?? '';
    _cargar();
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final repo = ref.read(requisicionesRepoProvider);
    if (repo == null) {
      if (mounted) setState(() => _cargado = true);
      return;
    }
    final almacenes = await repo.getAlmacenes();
    List<RequisicionItem> items = [];
    if (_editando) {
      final req = widget.requisicion!;
      for (final d in await repo.getDetalles(req.id)) {
        items.add(RequisicionItem(
          productoId: d.productoId,
          ingrediente: d.ingrediente,
          cantidad: d.cantidad,
          unidad: d.unidad.isEmpty ? 'unidad' : d.unidad,
        ));
      }
    }
    if (mounted) {
      setState(() {
        _almacenes = almacenes;
        _items = items;
        _origen = widget.requisicion?.origen ?? 'principal';
        _destino = widget.requisicion?.destino ?? 'restaurante';
        _cargado = true;
      });
    }
  }

  Future<void> _agregarProducto() async {
    final origen = _origen ?? 'principal';
    final producto = await showBuscadorProductos(context);
    if (producto == null || !mounted) return;
    final result = await showCantidadDialog(
      context,
      producto: producto,
      origen: origen,
    );
    if (result == null || !mounted) return;

    final idx =
        _items.indexWhere((i) => i.productoId == result.item.productoId);
    if (idx >= 0) {
      // Acumula cantidad/peso si el producto ya existe (como en form.py).
      final existente = _items[idx];
      final nuevoPeso = (existente.peso ?? 0) + result.peso;
      _items[idx] = RequisicionItem(
        productoId: existente.productoId,
        ingrediente: existente.ingrediente,
        cantidad: result.item.esPesable ? nuevoPeso : existente.cantidad + result.item.cantidad,
        unidad: existente.unidad,
        peso: result.item.esPesable ? nuevoPeso : existente.peso,
        esPesable: result.item.esPesable,
        verificado: existente.verificado,
      );
    } else {
      _items.add(result.item);
    }
    setState(() {});
    _snack('+ ${(producto['nombre'] as String?) ?? ''}');
  }

  void _eliminar(int index) {
    setState(() => _items.removeAt(index));
  }

  Future<void> _guardar() async {
    if (_items.isEmpty) {
      _snack('Agregue al menos un producto');
      return;
    }
    setState(() => _guardando = true);
    try {
      final repo = ref.read(requisicionesRepoProvider);
      if (repo == null) {
        throw Exception('Supabase no configurado');
      }
      await repo.guardarRequisicion(
        origen: _origen ?? 'principal',
        destino: _destino ?? 'restaurante',
        observaciones: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
        detalles: _items,
        editando: widget.requisicion,
      );
      if (mounted) {
        _snack(_editando
            ? 'Requisición actualizada'
            : 'Requisición creada: $_origen → $_destino');
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        final msg = 'Error: $e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: msg));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error copiado')),
              );
            },
            child: Text(msg),
          ),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Copiar',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: msg));
            },
          ),
        ));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_cargado) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(scheme),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _almacenesCard(scheme),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _obsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Observaciones',
                        hintText: 'Notas...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Productos (${_items.length})',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (_items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: Text(
                            'Sin productos agregados',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      for (var i = 0; i < _items.length; i++)
                        _productoRow(scheme, i, _items[i]),
                  ],
                ),
              ),
            ),
          ],
        ),
        // FAB para abrir el buscador de productos (abajo, estilo chat).
        Positioned(
          left: 0,
          right: 0,
          bottom: 20,
          child: Center(
            child: FloatingActionButton.extended(
              onPressed: _agregarProducto,
              heroTag: 'fab-agregar-producto',
              backgroundColor: scheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Agregar Producto'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(ColorScheme scheme) {
    final titulo = _editando ? 'Editar Requisición' : 'Nueva Requisición';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            tooltip: 'Volver',
            onPressed: _guardando ? null : widget.onBack,
          ),
          Expanded(
            child: Text(titulo,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            style: FilledButton.styleFrom(
              backgroundColor: _editando ? scheme.primary : Colors.green.shade700,
            ),
            child: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_editando ? 'Actualizar' : 'Crear'),
          ),
        ],
      ),
    );
  }

  Widget _almacenesCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  color: scheme.primary, size: 20),
              const SizedBox(width: 10),
              const Text('Ruta de Traslado',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          Divider(height: 12, color: scheme.outlineVariant),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Desde',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: _origen,
                      decoration: const InputDecoration(
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder()),
                      items: [
                        for (final a in _almacenes)
                          DropdownMenuItem(
                              value: a,
                              child: Text(
                                  a.isEmpty ? a : a[0].toUpperCase() + a.substring(1),
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _origen = v),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hacia',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: _destino,
                      decoration: const InputDecoration(
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder()),
                      items: [
                        for (final a in _almacenes)
                          DropdownMenuItem(
                              value: a,
                              child: Text(
                                  a.isEmpty ? a : a[0].toUpperCase() + a.substring(1),
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _destino = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _productoRow(ColorScheme scheme, int index, RequisicionItem item) {
    String display;
    if (item.esPesable) {
      display = '${item.cantidad.toStringAsFixed(3)} kg';
    } else {
      final cantidad = item.cantidad;
      display = cantidad == cantidad.roundToDouble()
          ? '${cantidad.toInt()} ${item.unidad}'
          : '${cantidad.toStringAsFixed(3)} ${item.unidad}';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${index + 1}. ${item.ingrediente}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
                Text(display,
                    style: TextStyle(
                        fontSize: 11, color: scheme.primary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            iconSize: 20,
            color: scheme.error,
            onPressed: () => _eliminar(index),
          ),
        ],
      ),
    );
  }
}
