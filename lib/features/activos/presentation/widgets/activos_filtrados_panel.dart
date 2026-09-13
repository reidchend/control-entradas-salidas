import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activo.dart';
import '../../data/activos_repository.dart';
import '../dialogs/activo_dialog.dart';
import '../dialogs/activos_filtro_dialog.dart';
import 'activo_card.dart';

/// Panel global de activos filtrados. Muestra todos los activos que cumplen
/// el filtro (de cualquier categoría), agrupados por categoría y grupo,
/// con opción de limpiar el filtro.
class ActivosFiltradosPanel extends ConsumerStatefulWidget {
  const ActivosFiltradosPanel({
    super.key,
    required this.repo,
    required this.filtro,
    required this.onLimpiar,
  });

  final ActivosRepository repo;
  final ActivosFiltro filtro;
  final VoidCallback onLimpiar;

  @override
  ConsumerState<ActivosFiltradosPanel> createState() =>
      _ActivosFiltradosPanelState();
}

class _ActivosFiltradosPanelState
    extends ConsumerState<ActivosFiltradosPanel> {
  late Future<List<Map<String, dynamic>>> _fut;

  @override
  void initState() {
    super.initState();
    _fut = _load();
  }

  @override
  void didUpdateWidget(ActivosFiltradosPanel old) {
    super.didUpdateWidget(old);
    if (old.filtro.categoriaId != widget.filtro.categoriaId ||
        old.filtro.grupo != widget.filtro.grupo ||
        old.filtro.ubicacion != widget.filtro.ubicacion ||
        old.filtro.estado != widget.filtro.estado) {
      _fut = _load();
    }
  }

  Future<List<Map<String, dynamic>>> _load() {
    final f = widget.filtro;
    return widget.repo.getActivosConFiltros(
      categoriaId: f.categoriaId,
      grupo: f.grupo,
      ubicacion: f.ubicacion,
      estado: f.estado,
    );
  }

  Future<void> _recargar() async {
    setState(() => _fut = _load());
  }

  Future<void> _editar(Map<String, dynamic> row) async {
    final activo = Activo.fromMap(row);
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

  Future<void> _desactivar(Map<String, dynamic> row) async {
    final activo = Activo.fromMap(row);
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

  Future<void> _eliminar(Map<String, dynamic> row) async {
    final activo = Activo.fromMap(row);
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final desc = widget.filtro.descripcion;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          color: colors.surfaceContainerHighest.withValues(alpha: .4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text('Filtro:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: colors.onSurfaceVariant)),
              for (final c in desc)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(c,
                      style: TextStyle(
                          fontSize: 11.5, color: colors.onSurfaceVariant)),
                ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Quitar filtro',
                onPressed: widget.onLimpiar,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _fut,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final filas = snap.data ?? const <Map<String, dynamic>>[];
              if (filas.isEmpty) {
                return Center(
                  child: Text(
                    'Sin activos con los filtros aplicados',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: _buildAgrupado(filas, colors),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAgrupado(
      List<Map<String, dynamic>> filas, ColorScheme colors) {
    final porCategoria = <String, List<Map<String, dynamic>>>{};
    for (final f in filas) {
      final cat = (f['categoria_nombre'] as String?) ?? 'Sin categoría';
      porCategoria.putIfAbsent(cat, () => []).add(f);
    }
    final cats = porCategoria.keys.toList()..sort();

    final out = <Widget>[];
    for (final cat in cats) {
      final items = porCategoria[cat]!;
      out.add(_SeccionHeader(
        titulo: cat,
        icono: Icons.category_outlined,
        color: colors.primary,
      ));
      final porGrupo = <String, List<Map<String, dynamic>>>{};
      for (final f in items) {
        final g = ((f['grupo'] as String?) ?? '').trim();
        porGrupo.putIfAbsent(g, () => []).add(f);
      }
      final grupos = porGrupo.keys.toList()
        ..sort((x, y) {
          if (x.isEmpty) return 1;
          if (y.isEmpty) return -1;
          return x.toLowerCase().compareTo(y.toLowerCase());
        });
      for (final g in grupos) {
        out.add(_SeccionHeader(
          titulo: g.isEmpty ? 'Sin grupo' : g,
          icono: Icons.folder_outlined,
          color: colors.onSurfaceVariant,
          pequeno: true,
        ));
        final gItems = porGrupo[g]!;
        for (var i = 0; i < gItems.length; i++) {
          final f = gItems[i];
          out.add(ActivoCard(
            activo: Activo.fromMap(f),
            onEdit: () => _editar(f),
            onDeactivate: () => _desactivar(f),
            onDelete: () => _eliminar(f),
          ));
          if (i < gItems.length - 1) {
            out.add(const Divider(height: 1, indent: 60));
          }
        }
      }
    }
    return out;
  }
}

/// Encabezado de sección reutilizable (categoría o grupo).
class _SeccionHeader extends StatelessWidget {
  const _SeccionHeader({
    required this.titulo,
    required this.icono,
    required this.color,
    this.pequeno = false,
  });

  final String titulo;
  final IconData icono;
  final Color color;
  final bool pequeno;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, pequeno ? 12 : 16, 12, 4),
      child: Row(
        children: [
          Icon(icono, size: pequeno ? 16 : 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: pequeno ? 13 : 15,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}