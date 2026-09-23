import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activo.dart';
import '../../data/activo_tipo.dart';
import '../../data/activos_filtro.dart';
import '../../data/activos_repository.dart';
import '../dialogs/unidad_dialog.dart';
import 'activo_card.dart';
import 'seccion_header.dart';

/// Panel de unidades que cumplen un filtro (de cualquier tipo/categoría),
/// agrupadas por categoría y tipo. También se usa como vista "por valor"
/// de una dimensión (ubicación, grupo, modelo, estado...) con título, botón
/// agregar y búsqueda local.
class ActivosFiltradosPanel extends ConsumerStatefulWidget {
  const ActivosFiltradosPanel({
    super.key,
    required this.repo,
    required this.filtro,
    required this.onLimpiar,
    this.titulo,
    this.onAgregar,
    this.searchTerm = '',
  });

  final ActivosRepository repo;
  final ActivosFiltro filtro;
  final VoidCallback onLimpiar;
  final String? titulo;
  final VoidCallback? onAgregar;
  final String searchTerm;

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
    final f = widget.filtro;
    final o = old.filtro;
    if (o.categoriaId != f.categoriaId ||
        o.grupo != f.grupo ||
        o.ubicacion != f.ubicacion ||
        o.modelo != f.modelo ||
        o.estado != f.estado ||
        old.searchTerm != widget.searchTerm) {
      _fut = _load();
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final f = widget.filtro;
    final filas = await widget.repo.getActivosConFiltros(
      categoriaId: f.categoriaId,
      grupo: f.grupo,
      ubicacion: f.ubicacion,
      modelo: f.modelo,
      estado: f.estado,
    );
    final q = widget.searchTerm.trim().toLowerCase();
    if (q.isEmpty) return filas;
    return filas.where((r) {
      final t = <String>[
        r['tipo_nombre'] as String? ?? '',
        r['modelo'] as String? ?? '',
        r['ubicacion'] as String? ?? '',
        r['grupo'] as String? ?? '',
      ].join(' ').toLowerCase();
      return t.contains(q);
    }).toList();
  }

  Future<void> _recargar() async {
    setState(() => _fut = _load());
  }

  Future<List<ActivoTipo>> _tipos() async {
    final maps = await widget.repo.getTipos();
    return [for (final m in maps) m['tipo'] as ActivoTipo];
  }

  Future<void> _editar(Map<String, dynamic> row) async {
    final activo = Activo.fromMap(row);
    final tipos = await _tipos();
    final categorias = await widget.repo.getCategorias();
    final ubicaciones = await widget.repo.getUbicaciones();
    if (!mounted) return;
    final editado = await showUnidadDialog(
      context,
      tipos: tipos,
      unidad: activo,
      categorias: categorias,
      onCrearTipo: (t) => widget.repo.createTipo(t),
      ubicacionesSugeridas: ubicaciones,
    );
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
        title: const Text('Desactivar unidad'),
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
        title: const Text('Eliminar unidad'),
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
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
          color: colors.surfaceContainerHighest.withValues(alpha: .4),
          child: Row(
            children: [
              if (widget.titulo != null) ...[
                Expanded(
                  child: Text(
                    widget.titulo!,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (widget.titulo == null && desc.isNotEmpty)
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final c in desc)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(c,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.onSurfaceVariant)),
                        ),
                    ],
                  ),
                ),
              if (widget.onAgregar != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Agregar unidad',
                  onPressed: widget.onAgregar,
                  visualDensity: VisualDensity.compact,
                ),
              ],
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Salir de esta vista',
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

  /// Unidades agrupadas por categoría y luego por tipo.
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
      out.add(SeccionHeader(
        titulo: cat,
        icono: Icons.category_outlined,
        color: colors.primary,
        conteo: items.length,
      ));
      final porTipo = <String, List<Map<String, dynamic>>>{};
      for (final f in items) {
        final t = ((f['tipo_nombre'] as String?) ?? '').trim();
        porTipo.putIfAbsent(t.isEmpty ? 'Sin nombre' : t, () => []).add(f);
      }
      final tipos = porTipo.keys.toList()..sort();
      for (final t in tipos) {
        out.add(SeccionHeader(
          titulo: t,
          icono: Icons.inventory_2_outlined,
          color: colors.onSurfaceVariant,
          pequeno: true,
          conteo: porTipo[t]!.length,
        ));
        final itemsTipo = porTipo[t]!;
        for (var i = 0; i < itemsTipo.length; i++) {
          final f = itemsTipo[i];
          out.add(ActivoCard(
            activo: Activo.fromMap(f),
            onEdit: () => _editar(f),
            onDeactivate: () => _desactivar(f),
            onDelete: () => _eliminar(f),
          ));
          if (i < itemsTipo.length - 1) {
            out.add(const Divider(height: 1, indent: 60));
          }
        }
      }
    }
    return out;
  }
}