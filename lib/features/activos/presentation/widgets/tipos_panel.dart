import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activo_tipo.dart';
import '../../data/activos_categoria.dart';
import '../../data/activos_repository.dart';
import '../dialogs/tipo_dialog.dart';
import '../dialogs/unidad_dialog.dart';
import 'seccion_header.dart';
import 'tipo_card.dart';

/// Panel de tipos del catálogo pertenecientes a una categoría, con búsqueda
/// interna y botones para crear tipos y agregar unidades.
class TiposPanel extends ConsumerStatefulWidget {
  const TiposPanel({
    super.key,
    required this.repo,
    required this.categoria,
    required this.searchTerm,
    required this.onOpenTipo,
  });

  final ActivosRepository repo;
  final ActivosCategoria categoria;
  final String searchTerm;
  final ValueChanged<ActivoTipo> onOpenTipo;

  @override
  ConsumerState<TiposPanel> createState() => _TiposPanelState();
}

class _TiposPanelState extends ConsumerState<TiposPanel> {
  late Future<List<Map<String, dynamic>>> _fut;

  @override
  void initState() {
    super.initState();
    _fut = _load();
  }

  @override
  void didUpdateWidget(TiposPanel old) {
    super.didUpdateWidget(old);
    if (old.searchTerm != widget.searchTerm ||
        old.categoria.id != widget.categoria.id) {
      _fut = _load();
    }
  }

  Future<List<Map<String, dynamic>>> _load() {
    return widget.repo.getTipos(
      categoriaId: widget.categoria.id,
      search: widget.searchTerm.isEmpty ? null : widget.searchTerm,
    );
  }

  Future<void> _recargar() async {
    final rebind = _load();
    setState(() => _fut = rebind);
  }

  Future<void> _crearTipo() async {
    final categorias = await widget.repo.getCategorias();
    final grupos = await widget.repo.getGrupos();
    final modelos = await widget.repo.getModelos();
    if (!mounted) return;
    final nuevo = await showTipoDialog(
      context,
      categorias: categorias,
      grupos: grupos,
      modelos: modelos,
    );
    if (nuevo == null) return;
    try {
      await widget.repo.createTipo(nuevo);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error al crear tipo: $e');
    }
  }

  Future<void> _editarTipo(ActivoTipo tipo) async {
    final categorias = await widget.repo.getCategorias();
    final grupos = await widget.repo.getGrupos();
    final modelos = await widget.repo.getModelos();
    if (!mounted) return;
    final editado = await showTipoDialog(
      context,
      tipo: tipo,
      categorias: categorias,
      grupos: grupos,
      modelos: modelos,
    );
    if (editado == null) return;
    try {
      await widget.repo.updateTipo(tipo.id, editado);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error al editar tipo: $e');
    }
  }

  Future<void> _desactivarTipo(ActivoTipo tipo) async {
    final ok = await _confirmar(
      'Desactivar tipo',
      '¿Desactivar "${tipo.nombre}"?',
      'Desactivar',
      destructive: false,
    );
    if (ok != true) return;
    try {
      await widget.repo.deactivateTipo(tipo.id);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _eliminarTipo(ActivoTipo tipo) async {
    final ok = await _confirmar(
      'Eliminar tipo',
      '¿Eliminar "${tipo.nombre}"?\nSus unidades también se eliminarán.',
      'Eliminar',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await widget.repo.deleteTipo(tipo.id);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _agregarUnidad(ActivoTipo tipo) async {
    final ubicaciones = await widget.repo.getUbicaciones();
    if (!mounted) return;
    final nueva = await showUnidadDialog(
      context,
      tipos: [tipo],
      tipoIdFijo: tipo.id,
      ubicacionesSugeridas: ubicaciones,
    );
    if (nueva == null) return;
    try {
      await widget.repo.createActivo(nueva);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error al agregar unidad: $e');
    }
  }

  Future<bool?> _confirmar(
    String titulo,
    String mensaje,
    String accion, {
    required bool destructive,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(accion),
          ),
        ],
      ),
    );
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
              Icon(Icons.category_outlined, size: 15, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.categoria.nombre,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: colors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Nuevo tipo',
                onPressed: _crearTipo,
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
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _fut,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final items = snap.data ?? const <Map<String, dynamic>>[];
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    widget.searchTerm.isNotEmpty
                        ? 'Sin resultados'
                        : 'Sin tipos en esta categoría',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: _buildAgrupado(items, colors),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Tipos agrupados por `grupo`, con headers de sección. Sin grupo al final.
  List<Widget> _buildAgrupado(
      List<Map<String, dynamic>> items, ColorScheme colors) {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final it in items) {
      final tipo = it['tipo'] as ActivoTipo;
      final g = (tipo.grupo ?? '').trim();
      grupos.putIfAbsent(g, () => []).add(it);
    }
    final llaves = grupos.keys.toList()
      ..sort((x, y) {
        if (x.isEmpty) return 1;
        if (y.isEmpty) return -1;
        return x.toLowerCase().compareTo(y.toLowerCase());
      });

    final filas = <Widget>[];
    for (final g in llaves) {
      final grupoItems = grupos[g]!;
      filas.add(SeccionHeader(
        titulo: g.isEmpty ? 'Sin grupo' : g,
        icono: Icons.folder_outlined,
        color: colors.primary,
        conteo: grupoItems.length,
      ));
      for (var i = 0; i < grupoItems.length; i++) {
        final it = grupoItems[i];
        final tipo = it['tipo'] as ActivoTipo;
        final unidades = (it['unidades'] as num?)?.toInt() ?? 0;
        filas.add(TipoCard(
          tipo: tipo,
          unidades: unidades,
          onOpen: () => widget.onOpenTipo(tipo),
          onAgregarUnidad: () => _agregarUnidad(tipo),
          onEdit: () => _editarTipo(tipo),
          onDeactivate: () => _desactivarTipo(tipo),
          onDelete: () => _eliminarTipo(tipo),
        ));
        if (i < grupoItems.length - 1) {
          filas.add(const Divider(height: 1, indent: 60));
        }
      }
    }
    return filas;
  }
}