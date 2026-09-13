import 'package:flutter/material.dart';

import '../../data/activos_categoria.dart';
import '../../data/activos_repository.dart';

const _estadosFiltro = ['Activo', 'Mantenimiento', 'Baja', 'Reservado', 'Traslado'];

/// Criterios de filtrado de activos. Todos los campos son opcionales.
class ActivosFiltro {
  const ActivosFiltro({
    this.categoriaId,
    this.categoriaNombre,
    this.grupo,
    this.ubicacion,
    this.estado,
  });

  final int? categoriaId;
  final String? categoriaNombre;
  final String? grupo;
  final String? ubicacion;
  final String? estado;

  bool get vacio =>
      categoriaId == null &&
      (grupo == null || grupo!.isEmpty) &&
      (ubicacion == null || ubicacion!.isEmpty) &&
      (estado == null || estado!.isEmpty);

  List<String> get descripcion {
    final lista = <String>[];
    if (categoriaNombre != null) lista.add('Categoría: $categoriaNombre');
    if (grupo != null && grupo!.isNotEmpty) lista.add('Grupo: $grupo');
    if (ubicacion != null && ubicacion!.isNotEmpty) lista.add('Ubicación: $ubicacion');
    if (estado != null && estado!.isNotEmpty) lista.add('Estado: $estado');
    return lista;
  }
}

/// Diálogo para seleccionar los filtros de activos.
/// Devuelve un [ActivosFiltro], o `null` si se canceló.
Future<ActivosFiltro?> showActivosFiltroDialog(
  BuildContext context,
  ActivosRepository repo, {
  ActivosFiltro? actual,
}) async {
  final categorias = await repo.getCategorias();
  final grupos = await repo.getGrupos();
  final ubicaciones = await repo.getUbicaciones();
  if (!context.mounted) return null;

  return showDialog<ActivosFiltro>(
    context: context,
    builder: (ctx) => _FiltroDialog(
      categorias: categorias,
      grupos: grupos,
      ubicaciones: ubicaciones,
      actual: actual,
    ),
  );
}

class _FiltroDialog extends StatefulWidget {
  const _FiltroDialog({
    required this.categorias,
    required this.grupos,
    required this.ubicaciones,
    this.actual,
  });

  final List<ActivosCategoria> categorias;
  final List<String> grupos;
  final List<String> ubicaciones;
  final ActivosFiltro? actual;

  @override
  State<_FiltroDialog> createState() => _FiltroDialogState();
}

class _FiltroDialogState extends State<_FiltroDialog> {
  late int? _categoriaId;
  late String? _categoriaNombre;
  late String? _grupo;
  late String? _ubicacion;
  late String? _estado;

  @override
  void initState() {
    super.initState();
    final a = widget.actual;
    _categoriaId = a?.categoriaId;
    _categoriaNombre = a?.categoriaNombre;
    _grupo = (a?.grupo ?? '').isEmpty ? null : a!.grupo;
    _ubicacion = (a?.ubicacion ?? '').isEmpty ? null : a!.ubicacion;
    _estado = (a?.estado ?? '').isEmpty ? null : a!.estado;
  }

  ActivosFiltro get _resultado => ActivosFiltro(
        categoriaId: _categoriaId,
        categoriaNombre: _categoriaNombre,
        grupo: _grupo,
        ubicacion: _ubicacion,
        estado: _estado,
      );

  void _limpiar() {
    setState(() {
      _categoriaId = null;
      _categoriaNombre = null;
      _grupo = null;
      _ubicacion = null;
      _estado = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tieneFiltros = !_resultado.vacio;

    return AlertDialog(
      title: const Text('Filtrar Activos'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selecciona uno o varios filtros para ver todos los activos '
              'que coincidan.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            _DropdownFiltro<int>(
              label: 'Categoría',
              valor: _categoriaId,
              opciones: [null, for (final c in widget.categorias) c.id],
              etiqueta: (id) {
                if (id == null) return 'Todas';
                return widget.categorias
                        .firstWhere((c) => c.id == id,
                            orElse: () => const ActivosCategoria(
                                id: -1, nombre: '', color: '', activo: true))
                        .nombre;
              },
              onChanged: (v) => setState(() {
                _categoriaId = v;
                _categoriaNombre = v == null
                    ? null
                    : widget.categorias
                        .firstWhere((c) => c.id == v)
                        .nombre;
              }),
            ),
            _DropdownFiltro<String>(
              label: 'Grupo',
              valor: _grupo,
              opciones: [null, ...widget.grupos],
              etiqueta: (g) => (g == null || g.isEmpty) ? 'Todos' : g,
              onChanged: (v) => setState(() => _grupo = v),
            ),
            _DropdownFiltro<String>(
              label: 'Ubicación',
              valor: _ubicacion,
              opciones: [null, ...widget.ubicaciones],
              etiqueta: (u) => (u == null || u.isEmpty) ? 'Todas' : u,
              onChanged: (v) => setState(() => _ubicacion = v),
            ),
            _DropdownFiltro<String>(
              label: 'Estado',
              valor: _estado,
              opciones: const [null, ..._estadosFiltro],
              etiqueta: (e) => (e == null || e.isEmpty) ? 'Todos' : e,
              onChanged: (v) => setState(() => _estado = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: tieneFiltros ? _limpiar : null,
          child: const Text('Limpiar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _resultado),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _DropdownFiltro<T> extends StatelessWidget {
  const _DropdownFiltro({
    required this.label,
    required this.valor,
    required this.opciones,
    required this.etiqueta,
    required this.onChanged,
  });

  final String label;
  final T? valor;
  final List<T?> opciones;
  final String Function(T?) etiqueta;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          DropdownButton<T>(
            value: valor,
            isExpanded: true,
            underline: const SizedBox(),
            items: [
              for (final o in opciones)
                DropdownMenuItem<T>(value: o, child: Text(etiqueta(o))),
            ],
            onChanged: (v) => onChanged(v),
          ),
        ],
      ),
    );
  }
}