import 'package:flutter/material.dart';

import '../../data/activo.dart';
import '../../data/activo_tipo.dart';
import '../../data/activos_categoria.dart';
import '../widgets/opciones_field.dart';
import 'tipo_dialog.dart';

const _estados = ['Activo', 'Mantenimiento', 'Baja', 'Reservado', 'Traslado'];

/// Diálogo crear/editar una unidad física de activo.
///
/// Cuando [tipoIdFijo] viene seteado (p.ej. agregar a un tipo concreto de
/// la vista de categorías) el tipo no es editable. En caso contrario se
/// elige un tipo del catálogo ([tipos]) o se crea uno nuevo con
/// [onCrearTipo].
Future<Activo?> showUnidadDialog(
  BuildContext context, {
  required List<ActivoTipo> tipos,
  int? tipoIdFijo,
  Activo? unidad,
  List<ActivosCategoria> categorias = const [],
  Future<int> Function(ActivoTipo tipo)? onCrearTipo,
  String? ubicacionPreset,
  String? estadoPreset,
  List<String> ubicacionesSugeridas = const [],
}) {
  return showDialog<Activo>(
    context: context,
    builder: (context) => _UnidadDialog(
      tipos: tipos,
      tipoIdFijo: tipoIdFijo,
      unidad: unidad,
      categorias: categorias,
      onCrearTipo: onCrearTipo,
      ubicacionPreset: ubicacionPreset,
      estadoPreset: estadoPreset,
      ubicacionesSugeridas: ubicacionesSugeridas,
    ),
  );
}

class _UnidadDialog extends StatefulWidget {
  const _UnidadDialog({
    required this.tipos,
    this.tipoIdFijo,
    this.unidad,
    this.categorias = const [],
    this.onCrearTipo,
    this.ubicacionPreset,
    this.estadoPreset,
    this.ubicacionesSugeridas = const [],
  });

  final List<ActivoTipo> tipos;
  final int? tipoIdFijo;
  final Activo? unidad;
  final List<ActivosCategoria> categorias;
  final Future<int> Function(ActivoTipo tipo)? onCrearTipo;
  final String? ubicacionPreset;
  final String? estadoPreset;
  final List<String> ubicacionesSugeridas;

  @override
  State<_UnidadDialog> createState() => _UnidadDialogState();
}

class _UnidadDialogState extends State<_UnidadDialog> {
  late final List<ActivoTipo> _tipos = [...widget.tipos];
  late int? _selected;
  ActivoTipo? _nuevo;

  late final TextEditingController _ubicacionCtrl;
  late final TextEditingController _valorCtrl;
  late final TextEditingController _fechaCtrl;
  late final TextEditingController _obsCtrl;
  late String _estado;

  @override
  void initState() {
    super.initState();
    final unidad = widget.unidad;
    final tipoActual = unidad?.tipoId;
    if (tipoActual != null && !_tipos.any((t) => t.id == tipoActual)) {
      _tipos.insert(
        0,
        ActivoTipo(
          id: tipoActual,
          nombre: (unidad?.tipoNombre ?? '').trim().isNotEmpty
              ? unidad!.tipoNombre!.trim()
              : 'Tipo $tipoActual',
          grupo: unidad?.grupo,
          modelo: unidad?.modelo,
          categoriaId: unidad?.categoriaId,
        ),
      );
    }
    _selected = widget.tipoIdFijo ?? unidad?.tipoId ?? -1;
    _ubicacionCtrl = TextEditingController(
        text: unidad?.ubicacion?.trim() ?? widget.ubicacionPreset ?? '');
    _estado = (unidad?.estado ?? widget.estadoPreset ?? 'Activo').trim();
    if (_estado.isEmpty || !_estados.contains(_estado)) _estado = 'Activo';
    _valorCtrl = TextEditingController(
        text: unidad != null && unidad.valor > 0
            ? unidad.valor.toStringAsFixed(2)
            : '');
    _fechaCtrl = TextEditingController(text: unidad?.fecha ?? '');
    _obsCtrl =
        TextEditingController(text: unidad?.observaciones?.trim() ?? '');
  }

  @override
  void dispose() {
    _ubicacionCtrl.dispose();
    _valorCtrl.dispose();
    _fechaCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  String _labelTipo(ActivoTipo t) {
    final extra = <String>[
      if ((t.modelo ?? '').trim().isNotEmpty) t.modelo!.trim(),
      if ((t.grupo ?? '').trim().isNotEmpty) t.grupo!.trim(),
    ];
    return extra.isEmpty ? t.nombre : '${t.nombre} · ${extra.join(' · ')}';
  }

  Future<void> _elegirNuevoTipo() async {
    final nuevo = await showTipoDialog(context, categorias: widget.categorias);
    if (nuevo == null) return;
    setState(() {
      _nuevo = nuevo;
      _selected = -1;
    });
  }

  Future<void> _guardar() async {
    final messenger = ScaffoldMessenger.of(context);
    var tipoId = _selected;
    if (tipoId == -1 || tipoId == null) {
      final nuevo = _nuevo;
      if (nuevo == null || widget.onCrearTipo == null) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Selecciona o crea un tipo'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      try {
        tipoId = await widget.onCrearTipo!(nuevo);
      } catch (e) {
        messenger.showSnackBar(SnackBar(
          content: Text('Error al crear el tipo: $e'),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      Activo(
        id: widget.unidad?.id ?? 0,
        tipoId: tipoId,
        ubicacion: _ubicacionCtrl.text.trim().isEmpty
            ? null
            : _ubicacionCtrl.text.trim(),
        estado: _estado,
        valor: double.tryParse(_valorCtrl.text.trim()) ?? 0,
        fecha: _fechaCtrl.text.trim().isEmpty
            ? null
            : _fechaCtrl.text.trim(),
        observaciones: _obsCtrl.text.trim().isEmpty
            ? null
            : _obsCtrl.text.trim(),
        activo: widget.unidad?.activo ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fijo = widget.tipoIdFijo;
    ActivoTipo? tipoFijo;
    if (fijo != null) {
      for (final t in _tipos) {
        if (t.id == fijo) {
          tipoFijo = t;
          break;
        }
      }
    }
    final descTipo = tipoFijo?.nombre ?? widget.unidad?.tipoNombre;

    return AlertDialog(
      title: Text(widget.unidad == null ? 'Agregar Unidad' : 'Editar Unidad'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fijo != null)
              _TipoFijoRow(nombre: descTipo ?? 'Tipo')
            else
              DropdownButtonFormField<int>(
                initialValue: _selected,
                decoration: const InputDecoration(labelText: 'Tipo *'),
                hint: const Text('Selecciona un tipo'),
                items: [
                  for (final t in _tipos)
                    DropdownMenuItem<int>(
                      value: t.id,
                      child: Text(
                        _labelTipo(t),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  DropdownMenuItem<int>(
                    value: -1,
                    child: Text(
                      _nuevo == null
                          ? '＋ Nuevo tipo...'
                          : '＋ Nuevo: ${_nuevo!.nombre}',
                      style: TextStyle(
                          color: colors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v == -1) {
                    _elegirNuevoTipo();
                    return;
                  }
                  setState(() {
                    _nuevo = null;
                    _selected = v;
                  });
                },
              ),
            const SizedBox(height: 12),
            OpcionesField(
              controller: _ubicacionCtrl,
              label: 'Ubicación',
              opciones: widget.ubicacionesSugeridas,
              icono: Icons.place_outlined,
            ),
            DropdownButtonFormField<String>(
              initialValue: _estado,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: [
                if (!_estados.contains(_estado))
                  DropdownMenuItem(value: _estado, child: Text(_estado)),
                for (final s in _estados)
                  DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) => setState(() => _estado = v ?? _estado),
            ),
            TextField(
              controller: _valorCtrl,
              decoration: const InputDecoration(labelText: 'Valor (Bs)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: _fechaCtrl,
              decoration: const InputDecoration(
                labelText: 'Fecha (AAAA-MM-DD)',
                hintText: '2025-01-15',
              ),
            ),
            TextField(
              controller: _obsCtrl,
              decoration: const InputDecoration(labelText: 'Observaciones'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Fila informativa del tipo fijo (no editable) dentro del diálogo.
class _TipoFijoRow extends StatelessWidget {
  const _TipoFijoRow({required this.nombre});
  final String nombre;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(nombre,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}