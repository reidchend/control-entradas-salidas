import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activo.dart';
import '../../data/activos_categoria.dart';
import '../../data/activos_repository.dart';
import '../dialogs/activo_dialog.dart';
import 'activo_card.dart';

/// Panel de activos pertenecientes a una categoría, con búsqueda interna
/// y botón para agregar activos (estilo ProductosPanel de Inventario).
class ActivosPanel extends ConsumerStatefulWidget {
  const ActivosPanel({
    super.key,
    required this.repo,
    required this.categoria,
    required this.searchTerm,
  });

  final ActivosRepository repo;
  final ActivosCategoria categoria;
  final String searchTerm;

  @override
  ConsumerState<ActivosPanel> createState() => _ActivosPanelState();
}

class _ActivosPanelState extends ConsumerState<ActivosPanel> {
  late Future<List<Activo>> _fut;

  @override
  void initState() {
    super.initState();
    _fut = _load();
  }

  @override
  void didUpdateWidget(ActivosPanel old) {
    super.didUpdateWidget(old);
    if (old.searchTerm != widget.searchTerm || old.categoria.id != widget.categoria.id) {
      _fut = _load();
    }
  }

  Future<List<Activo>> _load() {
    return widget.repo.getActivos(
      categoriaId: widget.categoria.id,
      search: widget.searchTerm.isEmpty ? null : widget.searchTerm,
    );
  }

  Future<void> _recargar() async {
    final rebind = _load();
    setState(() => _fut = rebind);
  }

  Future<void> _crear() async {
    final categorias = await widget.repo.getCategorias();
    final grupos = await widget.repo.getGrupos();
    if (!mounted) return;
    final nuevo = await showActivoDialog(
      context,
      categorias: categorias,
      grupos: grupos,
      activo: Activo(
        id: 0,
        nombre: '',
        categoriaId: widget.categoria.id,
      ),
    );
    if (nuevo == null) return;
    try {
      await widget.repo.createActivo(nuevo);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error al crear: $e');
    }
  }

  Future<void> _editar(Activo activo) async {
    final categorias = await widget.repo.getCategorias();
    final grupos = await widget.repo.getGrupos();
    if (!mounted) return;
    final editado = await showActivoDialog(context,
        activo: activo, categorias: categorias, grupos: grupos);
    if (editado == null) return;
    try {
      await widget.repo.updateActivo(activo.id, editado);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error al editar: $e');
    }
  }

  Future<void> _desactivar(Activo activo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desactivar activo'),
        content: Text('¿Desactivar "${activo.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repo.deactivateActivo(activo.id);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _eliminar(Activo activo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar activo'),
        content: Text('¿Eliminar definitivamente "${activo.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repo.deleteActivo(activo.id);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error: $e');
    }
  }

  /// Activos agrupados por `grupo`, con headers de sección. Sin grupo al final.
  List<Widget> _buildAgrupado(List<Activo> activos, ColorScheme colors) {
    final grupos = <String, List<Activo>>{};
    for (final a in activos) {
      final g = (a.grupo ?? '').trim();
      grupos.putIfAbsent(g, () => []).add(a);
    }
    final llaves = grupos.keys.toList()
      ..sort((x, y) {
        if (x.isEmpty) return 1;
        if (y.isEmpty) return -1;
        return x.toLowerCase().compareTo(y.toLowerCase());
      });

    final filas = <Widget>[];
    for (final g in llaves) {
      final items = grupos[g]!;
      filas.add(_GrupoHeader(
        nombre: g.isEmpty ? 'Sin grupo' : g,
        cantidad: items.length,
        color: colors.primary,
      ));
      for (var i = 0; i < items.length; i++) {
        final a = items[i];
        filas.add(ActivoCard(
          activo: a,
          onEdit: () => _editar(a),
          onDeactivate: () => _desactivar(a),
          onDelete: () => _eliminar(a),
        ));
        if (i < items.length - 1) {
          filas.add(const Divider(height: 1, indent: 60));
        }
      }
    }
    return filas;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 15, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.categoria.nombre,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: colors.primary),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Nuevo activo',
                onPressed: _crear,
              ),
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: 'Recargar',
                onPressed: _recargar,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Activo>>(
            future: _fut,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final activos = snap.data ?? const <Activo>[];
              if (activos.isEmpty) {
                return Center(
                  child: Text(
                    widget.searchTerm.isNotEmpty
                        ? 'Sin resultados'
                        : 'Sin activos en esta categoría',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: _buildAgrupado(activos, colors),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Encabezado de sección para un grupo de activos (nombre + conteo).
class _GrupoHeader extends StatelessWidget {
  const _GrupoHeader({
    required this.nombre,
    required this.cantidad,
    required this.color,
  });

  final String nombre;
  final int cantidad;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              nombre,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$cantidad',
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}