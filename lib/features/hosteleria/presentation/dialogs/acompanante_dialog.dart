import 'package:flutter/material.dart';

import '../forms/huesped_draft.dart';
import '../widgets/huesped_form.dart';

/// Diálogo para capturar/editar los datos de un acompañante.
/// Retorna el [HuespedDraft] aceptado o `null` si se cancela.
Future<HuespedDraft?> showAcompananteDialog(
  BuildContext context, {
  HuespedDraft? inicial,
}) {
  final draft = inicial?.copia() ?? HuespedDraft();
  return showDialog<HuespedDraft>(
    context: context,
    builder: (_) => _AcompananteDialog(draft: draft),
  );
}

class _AcompananteDialog extends StatefulWidget {
  const _AcompananteDialog({required this.draft});

  final HuespedDraft draft;

  @override
  State<_AcompananteDialog> createState() => _AcompananteDialogState();
}

class _AcompananteDialogState extends State<_AcompananteDialog> {
  String? _error;

  void _aceptar() {
    final err = widget.draft.errorValidacion;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, widget.draft);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Datos del acompañante'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HuespedForm(draft: widget.draft, onChanged: () {}),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _aceptar, child: const Text('Aceptar')),
      ],
    );
  }
}
