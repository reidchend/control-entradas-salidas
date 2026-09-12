import 'package:flutter/material.dart';

import '../../../../core/models/pos_models.dart';
import '../../../../core/utils/modal_sizing.dart';

/// Diálogo de selección de contornos (port de `_show_contornos_dialog`):
/// checkboxes de contornos activos, máximo 2 por plato. Devuelve la lista de
/// contornos seleccionados.
Future<List<PosPlato>> showContornosDialog(
  BuildContext context,
  PosPlato plato,
  List<PosPlato> contornos,
) async {
  return await showDialog<List<PosPlato>>(
        context: context,
        builder: (_) => _ContornosDialog(plato: plato, contornos: contornos),
      ) ??
      const [];
}

class _ContornosDialog extends StatefulWidget {
  const _ContornosDialog({required this.plato, required this.contornos});
  final PosPlato plato;
  final List<PosPlato> contornos;

  @override
  State<_ContornosDialog> createState() => _ContornosDialogState();
}

class _ContornosDialogState extends State<_ContornosDialog> {
  static const _maxSel = 2;
  final _seleccion = <int>{};
  String? _error;

  void _toggle(PosPlato c) {
    setState(() {
      if (_seleccion.contains(c.id)) {
        _seleccion.remove(c.id);
      } else {
        _seleccion.add(c.id);
      }
      _error = null;
    });
  }

  void _confirmar() {
    if (_seleccion.isEmpty) {
      setState(() => _error = 'Seleccione al menos un contorno');
      return;
    }
    if (_seleccion.length > _maxSel) {
      setState(() => _error = 'Máximo $_maxSel contornos');
      return;
    }
    Navigator.pop(context,
        [for (final c in widget.contornos) if (_seleccion.contains(c.id)) c]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Contornos para ${widget.plato.nombre}'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seleccione hasta $_maxSel contornos',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(fontSize: 11, color: scheme.error),
                ),
              const SizedBox(height: 8),
              for (final c in widget.contornos)
                CheckboxListTile(
                  value: _seleccion.contains(c.id),
                  onChanged: (_) => _toggle(c),
                  title: Text(c.nombre),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: Text(
                    '\$${c.precioVenta.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const <PosPlato>[]),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
