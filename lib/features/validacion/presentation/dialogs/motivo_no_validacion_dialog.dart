import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/modal_sizing.dart';
import '../../data/validacion_providers.dart';
import '../../data/validacion_repository.dart';
import '../widgets/motivos_chips.dart';

/// Diálogo para anotar el motivo por el que una entrada pendiente todavía no
/// se ha validado. Se elige un motivo frecuente con un toque o se escribe uno
/// nuevo a mano.
///
/// Devuelve `true` si se guardó o se quitó la nota, `null` si se canceló.
Future<bool?> mostrarMotivoNoValidacionDialog(
  BuildContext context, {
  required EntradaPendiente entrada,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _MotivoNoValidacionDialog(entrada: entrada),
  );
}

class _MotivoNoValidacionDialog extends ConsumerStatefulWidget {
  const _MotivoNoValidacionDialog({required this.entrada});

  final EntradaPendiente entrada;

  @override
  ConsumerState<_MotivoNoValidacionDialog> createState() =>
      _MotivoNoValidacionDialogState();
}

class _MotivoNoValidacionDialogState
    extends ConsumerState<_MotivoNoValidacionDialog> {
  late final TextEditingController _ctrl;
  bool _guardando = false;
  String? _error;

  bool get _tieneNota =>
      (widget.entrada.motivoNoValidacion ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ctrl =
        TextEditingController(text: widget.entrada.motivoNoValidacion ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _guardando) return;
    final repo = ref.read(motivosNoValidacionRepoProvider);
    if (repo == null) {
      setState(() => _error = 'Sin conexión a la base de datos');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await repo.guardarNota(widget.entrada.id, texto);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = 'No se pudo guardar: $e';
        });
      }
    }
  }

  Future<void> _quitar() async {
    final repo = ref.read(motivosNoValidacionRepoProvider);
    if (repo == null) {
      setState(() => _error = 'Sin conexión a la base de datos');
      return;
    }
    try {
      await repo.quitarNota(widget.entrada.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo quitar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = widget.entrada;

    return AlertDialog(
      title: const Text('Motivo de no validación'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              e.nombre,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${e.cantidadTexto} · ${e.almacen}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            MotivosChips(
              onSeleccionar: (texto) => setState(() {
                _ctrl.text = texto;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Escribe el motivo...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (_tieneNota)
          TextButton.icon(
            onPressed: _guardando ? null : _quitar,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Quitar nota'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed:
              (_guardando || _ctrl.text.trim().isEmpty) ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 18),
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}
