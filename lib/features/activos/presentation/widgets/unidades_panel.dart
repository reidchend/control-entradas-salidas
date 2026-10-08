import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/orden_natural.dart';
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
    if (old.searchTerm != widget.searchTerm || old.tipo.id != widget.tipo.id) {
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
    final estados = await widget.repo.getEstados();
    if (!mounted) return;
    await showUnidadDialog(
      context,
      tipos: [widget.tipo],
      tipoIdFijo: widget.tipo.id,
      estados: estados,
      onGuardar: (a) => widget.repo.createActivo(a),
      onCrearEstado: (n) => widget.repo.createEstado(n),
      onExisteUnidad: (t, u) => widget.repo.existeUnidad(t, u),
      ubicacionesSugeridas: ubicaciones,
    );
    if (mounted) await _recargar();
  }

  /// Todos los tipos activos, con el tipo actual asegurado aunque esté
  /// desactivado: al editar una unidad de este panel el tipo ya no viene fijo,
  /// así que debe poder elegirse cualquiera y no perder el actual.
  Future<List<ActivoTipo>> _todosLosTipos() async {
    final maps = await widget.repo.getTipos();
    final tipos = [for (final m in maps) m['tipo'] as ActivoTipo];
    if (!tipos.any((t) => t.id == widget.tipo.id)) {
      tipos.insert(0, widget.tipo);
    }
    return tipos;
  }

  /// Edita la unidad. A diferencia de agregar (siempre de este tipo), acá el
  /// tipo es editable: se puede mover la unidad a otro tipo o crear uno nuevo.
  Future<void> _editar(Activo activo) async {
    final tipos = await _todosLosTipos();
    final ubicaciones = await widget.repo.getUbicaciones();
    final estados = await widget.repo.getEstados();
    final categorias = await widget.repo.getCategorias();
    final grupos = await widget.repo.getGrupos();
    final modelos = await widget.repo.getModelos();
    if (!mounted) return;
    await showUnidadDialog(
      context,
      tipos: tipos,
      unidad: activo,
      categorias: categorias,
      estados: estados,
      grupos: grupos,
      modelos: modelos,
      onGuardar: (a) async {
        await widget.repo.updateActivo(activo.id, a);
        return a;
      },
      onCrearTipo: (t) => widget.repo.createTipo(t),
      onCrearEstado: (n) => widget.repo.createEstado(n),
      ubicacionesSugeridas: ubicaciones,
    );
    if (mounted) await _recargar();
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
        return compararNatural(x, y);
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
