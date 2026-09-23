import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activo.dart';
import '../../data/activo_tipo.dart';
import '../../data/activos_repository.dart';
import '../dialogs/unidad_dialog.dart';
import 'activo_card.dart';
import 'seccion_header.dart';

/// Panel de unidades físicas de un tipo concreto, agrupadas por ubicación,
/// con búsqueda interna y botón para agregar/editar/eliminar unidades.
class UnidadesPanel extends ConsumerStatefulWidget {
  const UnidadesPanel({
    super.key,
    required this.repo,
    required this.tipo,
    required this.searchTerm,
  });

  final ActivosRepository repo;
  final ActivoTipo tipo;
  final String searchTerm;

  @override
  ConsumerState<UnidadesPanel> createState() => _UnidadesPanelState();
}

class _UnidadesPanelState extends ConsumerState<UnidadesPanel> {
  late Future<List<Activo>> _fut;

  @override
  void initState() {
    super.initState();
    _fut = _load();
  }

  @override
  void didUpdateWidget(UnidadesPanel old) {
    super.didUpdateWidget(old);
    if (old.searchTerm != widget.searchTerm ||
        old.tipo.id != widget.tipo.id) {
      _fut = _load();
    }
  }

  Future<List<Activo>> _load() {
    return widget.repo.getUnidadesDeTipo(
      widget.tipo.id,
      search: widget.searchTerm.isEmpty ? null : widget.searchTerm,
    );
  }

  Future<void> _recargar() async {
    final rebind = _load();
    setState(() => _fut = rebind);
  }

  Future<void> _crearUnidad() async {
    final ubicaciones = await widget.repo.getUbicaciones();
    if (!mounted) return;
    final nueva = await showUnidadDialog(
      context,
      tipos: [widget.tipo],
      tipoIdFijo: widget.tipo.id,
      ubicacionesSugeridas: ubicaciones,
    );
    if (nueva == null) return;
    try {
      await widget.repo.createActivo(nueva);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error al crear unidad: $e');
    }
  }

  Future<void> _editar(Activo activo) async {
    final ubicaciones = await widget.repo.getUbicaciones();
    if (!mounted) return;
    final editado = await showUnidadDialog(
      context,
      tipos: [widget.tipo],
      tipoIdFijo: widget.tipo.id,
      unidad: activo,
      ubicacionesSugeridas: ubicaciones,
    );
    if (editado == null) return;
    try {
      await widget.repo.updateActivo(activo.id, editado);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error al editar unidad: $e');
    }
  }

  Future<void> _desactivar(Activo activo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desactivar unidad'),
        content: Text('¿Desactivar "${_ubicacion(activo)}"?'),
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
        title: const Text('Eliminar unidad'),
        content: Text('¿Eliminar definitivamente "${_ubicacion(activo)}"?'),
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

  String _ubicacion(Activo a) {
    final u = (a.ubicacion ?? '').trim();
    return u.isEmpty ? 'Sin ubicación' : u;
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
                  widget.tipo.nombre,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: colors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Nueva unidad',
                onPressed: _crearUnidad,
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
              final unidades = snap.data ?? const <Activo>[];
              if (unidades.isEmpty) {
                return Center(
                  child: Text(
                    widget.searchTerm.isNotEmpty
                        ? 'Sin resultados'
                        : 'Sin unidades de este tipo',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: _buildAgrupado(unidades, colors),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Unidades agrupadas por ubicación. Sin ubicación al final.
  List<Widget> _buildAgrupado(List<Activo> unidades, ColorScheme colors) {
    final porUbicacion = <String, List<Activo>>{};
    for (final a in unidades) {
      final u = (a.ubicacion ?? '').trim();
      porUbicacion.putIfAbsent(u, () => []).add(a);
    }
    final llaves = porUbicacion.keys.toList()
      ..sort((x, y) {
        if (x.isEmpty) return 1;
        if (y.isEmpty) return -1;
        return x.toLowerCase().compareTo(y.toLowerCase());
      });

    final filas = <Widget>[];
    for (final u in llaves) {
      final items = porUbicacion[u]!;
      filas.add(SeccionHeader(
        titulo: u.isEmpty ? 'Sin ubicación' : u,
        icono: Icons.place_outlined,
        color: colors.primary,
        conteo: items.length,
      ));
      for (var i = 0; i < items.length; i++) {
        final a = items[i];
        filas.add(ActivoCard(
          activo: a,
          mostrarTipo: false,
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
}