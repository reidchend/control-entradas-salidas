import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activo_tipo.dart';
import '../../data/activos_repository.dart';
import '../dialogs/confirmar_dialog.dart';
import '../dialogs/tipo_dialog.dart';
import '../dialogs/unidad_dialog.dart';
import 'activos_tipo_card.dart';
import 'seccion_header.dart';

/// Grilla raíz de tipos del catálogo, agrupada por categoría (un header por
/// categoría). Es la vista principal de la pantalla: todos los tipos con su
/// conteo de unidades, manteniendo el contexto de categoría y con las mismas
/// acciones del panel dentro de una categoría.
class ActivosTiposGrid extends ConsumerStatefulWidget {
  const ActivosTiposGrid({
    super.key,
    required this.repo,
    required this.searchTerm,
    required this.onOpenTipo,
  });

  final ActivosRepository repo;
  final String searchTerm;
  final ValueChanged<ActivoTipo> onOpenTipo;

  @override
  ConsumerState<ActivosTiposGrid> createState() => _ActivosTiposGridState();
}

class _ActivosTiposGridState extends ConsumerState<ActivosTiposGrid> {
  late Future<List<Map<String, dynamic>>> _fut;

  @override
  void initState() {
    super.initState();
    _fut = _load();
  }

  @override
  void didUpdateWidget(ActivosTiposGrid old) {
    super.didUpdateWidget(old);
    if (old.searchTerm != widget.searchTerm) {
      _fut = _load();
    }
  }

  Future<List<Map<String, dynamic>>> _load() {
    return widget.repo.getTipos(
      search: widget.searchTerm.isEmpty ? null : widget.searchTerm,
    );
  }

  Future<void> _recargar() async {
    final rebind = _load();
    setState(() => _fut = rebind);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, dynamic>>>(
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
                  : 'Sin tipos en el catálogo',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          children: _buildAgrupado(items, colors),
        );
      },
    );
  }

  /// Tipos agrupados por categoría, con headers de sección. 'Sin categoría'
  /// al final.
  List<Widget> _buildAgrupado(
      List<Map<String, dynamic>> items, ColorScheme colors) {
    final porCategoria = <String, List<Map<String, dynamic>>>{};
    for (final it in items) {
      final cat =
          ((it['categoria_nombre'] as String?) ?? 'Sin categoría').trim();
      porCategoria.putIfAbsent(cat, () => []).add(it);
    }
    final llaves = porCategoria.keys.toList()
      ..sort((x, y) {
        if (x == 'Sin categoría') return 1;
        if (y == 'Sin categoría') return -1;
        return x.toLowerCase().compareTo(y.toLowerCase());
      });

    final filas = <Widget>[];
    for (final cat in llaves) {
      final itemsCat = porCategoria[cat]!;
      filas.add(SeccionHeader(
        titulo: cat,
        icono: Icons.category_outlined,
        color: colors.primary,
        conteo: itemsCat.length,
      ));
      filas.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final it in itemsCat)
              ActivosTipoCard(
                tipo: it['tipo'] as ActivoTipo,
                unidades: (it['unidades'] as num?)?.toInt() ?? 0,
                onOpen: () => widget.onOpenTipo(it['tipo'] as ActivoTipo),
                onAgregarUnidad: () =>
                    _agregarUnidad(it['tipo'] as ActivoTipo),
                onEdit: () => _editarTipo(it['tipo'] as ActivoTipo),
                onDeactivate: () =>
                    _desactivarTipo(it['tipo'] as ActivoTipo),
                onDelete: () => _eliminarTipo(it['tipo'] as ActivoTipo),
              ),
          ],
        ),
      ));
    }
    return filas;
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
    final ok = await showConfirmarDialog(
      context,
      titulo: 'Desactivar tipo',
      mensaje: '¿Desactivar "${tipo.nombre}"?',
      accion: 'Desactivar',
    );
    if (!ok) return;
    try {
      await widget.repo.deactivateTipo(tipo.id);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _eliminarTipo(ActivoTipo tipo) async {
    final ok = await showConfirmarDialog(
      context,
      titulo: 'Eliminar tipo',
      mensaje: '¿Eliminar "${tipo.nombre}"?\nSus unidades también se eliminarán.',
      accion: 'Eliminar',
    );
    if (!ok) return;
    try {
      await widget.repo.deleteTipo(tipo.id);
      if (mounted) await _recargar();
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _agregarUnidad(ActivoTipo tipo) async {
    final ubicaciones = await widget.repo.getUbicaciones();
    final estados = await widget.repo.getEstados();
    if (!mounted) return;
    await showUnidadDialog(
      context,
      tipos: [tipo],
      tipoIdFijo: tipo.id,
      estados: estados,
      onGuardar: (a) => widget.repo.createActivo(a),
      onCrearEstado: (n) => widget.repo.createEstado(n),
      onExisteUnidad: (t, u) => widget.repo.existeUnidad(t, u),
      ubicacionesSugeridas: ubicaciones,
    );
    if (mounted) await _recargar();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }
}