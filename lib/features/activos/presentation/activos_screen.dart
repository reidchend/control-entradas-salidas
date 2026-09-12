import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/activo.dart';
import '../data/activos_providers.dart';
import '../data/activos_repository.dart';
import 'dialogs/activo_dialog.dart';
import 'widgets/activo_card.dart';

/// Pantalla de Inventario de Activos — CRUD de bienes.
class ActivosScreen extends ConsumerStatefulWidget {
  const ActivosScreen({super.key});

  @override
  ConsumerState<ActivosScreen> createState() => _ActivosScreenState();
}

class _ActivosScreenState extends ConsumerState<ActivosScreen> {
  String _search = '';
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(activosRepoProvider)!;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: _onScreenKey,
        child: Column(
          children: [
            _buildHeader(repo, colors),
            Expanded(child: _buildListado(colors)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _crear(repo),
        tooltip: 'Nuevo activo',
        child: const Icon(Icons.add),
      ),
    );
  }

  KeyEventResult _onScreenKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.f1) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildHeader(ActivosRepository repo, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                hintText: 'Buscar activo... (F1)',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colors.surfaceContainerHighest,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Recargar',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildListado(ColorScheme colors) {
    final repo = ref.watch(activosRepoProvider)!;
    return FutureBuilder<List<Activo>>(
      future: repo.getActivos(search: _search.isEmpty ? null : _search),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text(
              'Error: ${snap.error}',
              style: TextStyle(color: colors.error),
            ),
          );
        }
        final activos = snap.data ?? const <Activo>[];
        if (activos.isEmpty) {
          return Center(
            child: Text(
              _search.isEmpty ? 'No hay activos registrados' : 'Sin resultados',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          );
        }
        return ListView.builder(
          itemCount: activos.length,
          itemBuilder: (context, i) {
            final a = activos[i];
            return ActivoCard(
              activo: a,
              onEdit: () => _editar(repo, a),
              onDeactivate: () => _desactivar(repo, a),
              onDelete: () => _eliminar(repo, a),
            );
          },
        );
      },
    );
  }

  Future<void> _crear(ActivosRepository repo) async {
    final nuevo = await showActivoDialog(context);
    if (nuevo == null) return;
    try {
      await repo.createActivo(nuevo);
      setState(() {});
    } catch (e) {
      _snack('Error al crear: $e');
    }
  }

  Future<void> _editar(ActivosRepository repo, Activo activo) async {
    final editado = await showActivoDialog(context, activo: activo);
    if (editado == null) return;
    try {
      await repo.updateActivo(activo.id, editado);
      setState(() {});
    } catch (e) {
      _snack('Error al editar: $e');
    }
  }

  Future<void> _desactivar(ActivosRepository repo, Activo activo) async {
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
      await repo.deactivateActivo(activo.id);
      setState(() {});
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _eliminar(ActivosRepository repo, Activo activo) async {
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
      await repo.deleteActivo(activo.id);
      setState(() {});
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
}