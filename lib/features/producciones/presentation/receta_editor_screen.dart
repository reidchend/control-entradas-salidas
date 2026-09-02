import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/producto.dart';
import '../../../core/models/receta.dart';
import '../data/producciones_providers.dart';
import '../data/producciones_repository.dart';

/// Editor de receta en pantalla completa (estilo wizard) — porta
/// `receta_editor.py`. Muestra header, secciones de datos/producto/
/// componentes con buscador de productos y resumen al pie.
class RecetaEditorScreen extends ConsumerStatefulWidget {
  const RecetaEditorScreen({super.key, this.receta, this.onSaved, this.onCancel});

  /// Receta a editar; `null` → nueva receta.
  final Receta? receta;
  final VoidCallback? onSaved;
  final VoidCallback? onCancel;

  @override
  ConsumerState<RecetaEditorScreen> createState() => _RecetaEditorScreenState();
}

class _CompRow {
  int? productoId;
  final TextEditingController cantidadCtrl = TextEditingController(text: '1');
  final TextEditingController unidadCtrl =
      TextEditingController(text: 'unidad');
}

class _RecetaEditorScreenState extends ConsumerState<RecetaEditorScreen> {
  final _nombreCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController(text: '1');
  final _searchCtrl = TextEditingController();

  bool get _angosto => MediaQuery.of(context).size.width < 600;
  final _baseSearchCtrl = TextEditingController();
  final _finalSearchCtrl = TextEditingController();

  String _tipo = 'compuesta';
  Producto? _baseProducto;
  Producto? _finalProducto;
  final List<_CompRow> _componentes = [];

  Map<int, double> _stock = {};
  bool _editando = false;

  @override
  void initState() {
    super.initState();
    _editando = widget.receta != null;
    final r = widget.receta;
    if (r != null) {
      _nombreCtrl.text = r.nombre;
      _cantidadCtrl.text = _fmtCant(r.cantidadProducida);
      _tipo = r.tipo;
    } else {
      _tipo = 'simple';
    }
    _cargarInicial();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _cantidadCtrl.dispose();
    _searchCtrl.dispose();
    _baseSearchCtrl.dispose();
    _finalSearchCtrl.dispose();
    for (final c in _componentes) {
      c.cantidadCtrl.dispose();
      c.unidadCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarInicial() async {
    final repo = ref.read(produccionesRepoProvider)!;
    final stock = await repo.stockTotalPorProducto();
    if (!mounted) return;
    setState(() => _stock = stock);

    final r = widget.receta;
    if (r == null) return;
    final productos = await repo.getProductosActivos();
    if (r.productoBaseId != null) {
      _baseProducto = productos
          .where((p) => p.id == r.productoBaseId)
          .firstOrNull;
    }
    if (r.productoFinalId != null) {
      _finalProducto = productos
          .where((p) => p.id == r.productoFinalId)
          .firstOrNull;
    }
    final componentes = await repo.getComponentes(r.id);
    if (!mounted) return;
    setState(() {
      _baseProducto = _baseProducto;
      _finalProducto = _finalProducto;
      for (final c in componentes) {
        final row = _CompRow()
          ..productoId = c.productoId
          ..cantidadCtrl.text = _fmtCant(c.cantidad)
          ..unidadCtrl.text = c.unidad;
        _componentes.add(row);
      }
    });
  }

  bool get _esSimple => _tipo == 'simple';

  String _fmtCant(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(3);
  }

  void _onTipoChange(String? tipo) {
    if (tipo == null || tipo == _tipo) return;
    setState(() => _tipo = tipo);
    if (_componentes.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cambiar de tipo puede requerir redefinir los componentes.')),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Búsqueda de productos (sección componentes)
  // ---------------------------------------------------------------------

  List<Producto> _buscar(String texto, List<Producto> productos) {
    final term = texto.toLowerCase().trim();
    if (term.isEmpty) return [];
    return productos
        .where((p) => p.activo && p.nombre.toLowerCase().contains(term))
        .take(8)
        .toList();
  }

  void _agregarProducto(Producto p) {
    setState(() {
      final esPesable = p.esPesable;
      final row = _CompRow()
        ..productoId = p.id
        ..cantidadCtrl.text = '1'
        ..unidadCtrl.text = esPesable ? 'kg' : p.unidadMedida;
      _componentes.add(row);
      _searchCtrl.clear();
    });
  }

  void _agregarFilaVacia() {
    setState(() {
      _componentes.add(_CompRow());
      _searchCtrl.clear();
    });
  }

  void _quitarFila(int index) {
    setState(() {
      final row = _componentes.removeAt(index);
      row.cantidadCtrl.dispose();
      row.unidadCtrl.dispose();
    });
  }

  String get _tipoComponente => _esSimple ? 'RESULTADO' : 'INGREDIENTE';

  // ---------------------------------------------------------------------
  // Guardar / cancelar
  // ---------------------------------------------------------------------

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre de la receta es requerido')),
      );
      return;
    }

    final cantidad = double.tryParse(_cantidadCtrl.text.trim().replaceAll(',', '.'));
    if (cantidad == null || cantidad <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una cantidad base válida')),
      );
      return;
    }

    if (_esSimple && _baseProducto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona el producto base')),
      );
      return;
    }
    if (!_esSimple && _finalProducto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona el producto final')),
      );
      return;
    }

    final componentes = <RecetaComponenteInput>[
      for (final row in _componentes)
        if (row.productoId != null)
          RecetaComponenteInput(
            productoId: row.productoId!,
            cantidad: double.tryParse(
                    row.cantidadCtrl.text.trim().replaceAll(',', '.')) ??
                1,
            tipoComponente: _tipoComponente,
            unidad: row.unidadCtrl.text.trim().isEmpty
                ? 'unidad'
                : row.unidadCtrl.text.trim(),
            pesoVariable: 0,
          ),
    ];

    try {
      await ref.read(produccionesRepoProvider)!.saveReceta(
            nombre: nombre,
            tipo: _tipo,
            cantidadProducida: cantidad,
            productoBaseId: _esSimple ? _baseProducto?.id : null,
            productoFinalId: _esSimple ? null : _finalProducto?.id,
            componentes: componentes,
            recetaId: _editando ? widget.receta!.id : null,
            activo: _editando ? (widget.receta!.activo ? 1 : 0) : 1,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receta guardada correctamente')),
        );
      }
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar receta: $e')),
        );
      }
    }
  }

  void _cancelar() => widget.onCancel?.call();

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final productosAsync = ref.watch(productosActivosProvider);

    return Column(
      children: [
        _header(scheme),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionBasicos(scheme),
                const SizedBox(height: 20),
                _sectionProducto(scheme, productosAsync),
                const SizedBox(height: 20),
                _sectionComponentes(scheme, productosAsync),
              ],
            ),
          ),
        ),
        _footer(scheme),
      ],
    );
  }

  Widget _header(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Volver a Recetas',
            onPressed: _cancelar,
          ),
          Icon(Icons.description_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editando
                    ? 'Editar Receta · ${widget.receta!.nombre}'
                    : 'Nueva Receta',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                'Define cómo se fabrica este producto a partir de sus ingredientes.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionBasicos(ColorScheme scheme) {
    return _section(
      scheme,
      title: 'Datos básicos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nombreCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre de la Receta',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _cantidadCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Cantidad Base (por batch)',
                hintText: 'Ej: 1 (kg, bandejas, unidades...)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Tipo de Receta',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'simple',
                label: Text(_angosto
                    ? 'Simple'
                    : 'Simple · parte un producto en sus derivados'),
              ),
              ButtonSegment(
                value: 'compuesta',
                label: Text(_angosto
                    ? 'Compuesta'
                    : 'Compuesta · fabrica un producto desde ingredientes'),
              ),
            ],
            selected: {_tipo},
            showSelectedIcon: false,
            expandedInsets: _angosto ? EdgeInsets.zero : null,
            onSelectionChanged: (s) => _onTipoChange(s.first),
          ),
        ],
      ),
    );
  }

  Widget _sectionProducto(
      ColorScheme scheme, AsyncValue<List<Producto>> productosAsync) {
    return _section(
      scheme,
      title: 'Producto',
      child: productosAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Error cargando productos: $e'),
        data: (productos) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_esSimple)
              Expanded(
                child: _selectorProducto(
                  scheme,
                  productos,
                  label: 'Producto Base (origen)',
                  hint: 'Producto que se va a partir/descomponer',
                  selected: _baseProducto,
                  searchCtrl: _baseSearchCtrl,
                  onSelect: (p) => setState(() => _baseProducto = p),
                  onClear: () => setState(() {
                    _baseProducto = null;
                    _baseSearchCtrl.clear();
                  }),
                ),
              )
            else
              Expanded(
                child: _selectorProducto(
                  scheme,
                  productos,
                  label: 'Producto Final (resultado)',
                  hint: 'Producto que se obtiene al fabricar',
                  selected: _finalProducto,
                  searchCtrl: _finalSearchCtrl,
                  onSelect: (p) => setState(() => _finalProducto = p),
                  onClear: () => setState(() {
                    _finalProducto = null;
                    _finalSearchCtrl.clear();
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _selectorProducto(
    ColorScheme scheme,
    List<Producto> productos, {
    required String label,
    required String hint,
    required Producto? selected,
    required TextEditingController searchCtrl,
    required ValueChanged<Producto> onSelect,
    required VoidCallback onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        Text(hint,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        TextField(
          controller: searchCtrl,
          decoration: const InputDecoration(
            hintText: 'Escribe el nombre...',
            prefixIcon: Icon(Icons.search),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (searchCtrl.text.trim().isNotEmpty)
          Column(
            children: [
              for (final p in _buscar(searchCtrl.text, productos))
                InkWell(
                  onTap: () {
                    onSelect(p);
                    searchCtrl.clear();
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.nombre,
                                  style: const TextStyle(fontWeight: FontWeight.w500)),
                              Text(
                                'Stock: ${_fmtCant(_stock[p.id] ?? 0)} ${p.unidadMedida}',
                                style: TextStyle(
                                    fontSize: 11, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.check_circle_outline,
                            size: 18, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
              if (_buscar(searchCtrl.text, productos).isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Sin resultados',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  selected?.nombre ?? 'Ninguno seleccionado',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selected != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Limpiar selección',
                  onPressed: onClear,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionComponentes(
      ColorScheme scheme, AsyncValue<List<Producto>> productosAsync) {
    return _section(
      scheme,
      title: _esSimple ? 'Producto final' : 'Ingredientes',
      subtitle: _esSimple
          ? 'Productos resultantes (lo que se obtiene)'
          : 'Ingredientes (lo que se consume)',
      child: productosAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Error cargando productos: $e'),
        data: (productos) {
          final resultados = _buscar(_searchCtrl.text, productos);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Buscar producto para agregar',
                  hintText: 'Escribe el nombre...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              if (_searchCtrl.text.trim().isNotEmpty)
                Column(
                  children: [
                    for (final p in resultados)
                      InkWell(
                        onTap: () => _agregarProducto(p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: scheme.outlineVariant),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.nombre,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500)),
                                    Text(
                                      'Stock: ${_fmtCant(_stock[p.id] ?? 0)} ${p.unidadMedida}'
                                      '${p.esPesable ? ' · pesable' : ''}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.add_circle, color: scheme.primary),
                            ],
                          ),
                        ),
                      ),
                    if (resultados.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('Sin resultados',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              const Divider(),
              for (var i = 0; i < _componentes.length; i++)
                _componentRow(scheme, productos, i),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: Text(_esSimple
                    ? '+ Agregar ingrediente'
                    : '+ Agregar manualmente'),
                onPressed: _agregarFilaVacia,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _componentRow(
      ColorScheme scheme, List<Producto> productos, int index) {
    final row = _componentes[index];
    final dropdown = DropdownButtonFormField<int>(
      initialValue: row.productoId,
      isExpanded: true,
      hint: const Text('Producto...'),
      items: [
        for (final p in productos)
          if (p.activo)
            DropdownMenuItem(
              value: p.id,
              child: Text(p.nombre, overflow: TextOverflow.ellipsis),
            ),
      ],
      onChanged: (v) => setState(() => row.productoId = v),
    );
    final cantField = TextField(
      controller: row.cantidadCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'Cant.',
        border: OutlineInputBorder(),
      ),
    );
    final unidadField = TextField(
      controller: row.unidadCtrl,
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'unidad',
        border: OutlineInputBorder(),
      ),
    );
    final deleteBtn = IconButton(
      icon: Icon(Icons.delete_outline, color: scheme.error),
      tooltip: 'Quitar',
      onPressed: () => _quitarFila(index),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: _angosto
          ? Column(
              children: [
                dropdown,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: cantField),
                    const SizedBox(width: 8),
                    Expanded(child: unidadField),
                    const SizedBox(width: 4),
                    deleteBtn,
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: dropdown),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: cantField),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: unidadField),
                deleteBtn,
              ],
            ),
    );
  }

  Widget _footer(ColorScheme scheme) {
    final angosto = MediaQuery.of(context).size.width < 600;
    final texto = Text(
      '${_componentes.length} componentes · cantidad editable al descargar',
      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
    );
    final botones = Row(
      children: [
        OutlinedButton(
          onPressed: _cancelar,
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar'),
          onPressed: _guardar,
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: angosto
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                texto,
                const SizedBox(height: 12),
                botones,
              ],
            )
          : Row(
              children: [
                Expanded(child: texto),
                const SizedBox(width: 12),
                botones,
              ],
            ),
    );
  }

  Widget _section(
    ColorScheme scheme, {
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle,
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
