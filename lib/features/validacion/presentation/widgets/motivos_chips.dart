import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/motivos_no_validacion_repository.dart';
import '../../data/validacion_providers.dart';

/// Chips de motivos frecuentes con gestión inline.
///
/// - Tocar un chip copia su texto con [onSeleccionar] (para pegarlo en el
///   cuadro de motivo del diálogo).
/// - El botón de edición muestra un ✕ en cada chip para borrarlo.
/// - El botón "+" agrega un motivo nuevo al catálogo compartido.
class MotivosChips extends ConsumerStatefulWidget {
  const MotivosChips({super.key, required this.onSeleccionar});

  final ValueChanged<String> onSeleccionar;

  @override
  ConsumerState<MotivosChips> createState() => _MotivosChipsState();
}

class _MotivosChipsState extends ConsumerState<MotivosChips> {
  bool _editando = false;
  bool _agregando = false;
  final _nuevoCtrl = TextEditingController();
  String? _mensaje;

  @override
  void dispose() {
    _nuevoCtrl.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    final texto = _nuevoCtrl.text.trim();
    if (texto.isEmpty) return;
    final repo = ref.read(motivosNoValidacionRepoProvider);
    if (repo == null) {
      setState(() => _mensaje = 'Sin conexión a la base de datos');
      return;
    }
    try {
      final ok = await repo.crear(texto);
      if (!mounted) return;
      if (ok) {
        _nuevoCtrl.clear();
        setState(() {
          _agregando = false;
          _mensaje = null;
        });
        ref.invalidate(motivosPredefinidosProvider);
      } else {
        setState(() => _mensaje = 'Ese motivo ya existe');
      }
    } catch (e) {
      if (mounted) setState(() => _mensaje = 'No se pudo guardar: $e');
    }
  }

  Future<void> _eliminar(MotivoNoValidacion motivo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar motivo'),
        content: Text('¿Borrar el motivo "${motivo.texto}" de la lista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    final repo = ref.read(motivosNoValidacionRepoProvider);
    if (repo == null) return;
    try {
      await repo.eliminar(motivo.id);
      if (mounted) ref.invalidate(motivosPredefinidosProvider);
    } catch (e) {
      if (mounted) setState(() => _mensaje = 'No se pudo eliminar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motivosAsync = ref.watch(motivosPredefinidosProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Motivos frecuentes',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: Icon(_editando ? Icons.close : Icons.edit_outlined),
              tooltip: _editando
                  ? 'Terminar de editar'
                  : 'Editar o borrar motivos guardados',
              onPressed: () => setState(() {
                _editando = !_editando;
                _agregando = false;
                _mensaje = null;
              }),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              icon: const Icon(Icons.add),
              tooltip: 'Agregar motivo frecuente',
              onPressed: () => setState(() {
                _agregando = !_agregando;
                _mensaje = null;
              }),
            ),
          ],
        ),
        if (_agregando)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nuevoCtrl,
                  autofocus: true,
                  isDense: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Ej: Falta factura del proveedor...',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onSubmitted: (_) => _crear(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _crear,
                child: const Text('Agregar'),
              ),
            ],
          ),
        if (_mensaje != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _mensaje!,
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          ),
        const SizedBox(height: 6),
        motivosAsync.when(
          loading: () => const SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (e, _) => Text(
            'No se pudo cargar el catálogo de motivos '
            '(¿falta la migración 20261019000000?).',
            style: TextStyle(fontSize: 12, color: scheme.error),
          ),
          data: (lista) => lista.isEmpty
              ? Text(
                  'Aún no hay motivos guardados; escribe el motivo abajo.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final m in lista)
                      InputChip(
                        label: Text(
                          m.texto,
                          style: const TextStyle(fontSize: 13),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed:
                            _editando ? null : () => widget.onSeleccionar(m.texto),
                        onDeleted: _editando ? () => _eliminar(m) : null,
                        deleteIconColor: scheme.error,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
