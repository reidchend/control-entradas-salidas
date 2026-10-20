import 'package:flutter/material.dart';

import '../widgets/cantidad_stepper.dart';

/// Pide una cantidad nueva para un grupo de unidades.
///
/// Devuelve `null` si se cancela. El ajuste real (crear o eliminar la
/// diferencia) lo hace quien llama, que además confirma las bajas.
Future<int?> showCantidadUnidadesDialog(
  BuildContext context, {
  required int cantidadActual,
  int max = 500,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _CantidadDialog(
      cantidadActual: cantidadActual,
      max: max,
    ),
  );
}

class _CantidadDialog extends StatefulWidget {
  const _CantidadDialog({
    required this.cantidadActual,
    required this.max,
  });

  final int cantidadActual;
  final int max;

  @override
  State<_CantidadDialog> createState() => _CantidadDialogState();
}

class _CantidadDialogState extends State<_CantidadDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: '${widget.cantidadActual}');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _aplicar() {
    final n = int.tryParse(_ctrl.text.trim()) ?? widget.cantidadActual;
    Navigator.pop(context, n.clamp(1, widget.max));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final actual = widget.cantidadActual;
    return AlertDialog(
      title: const Text('Cambiar cantidad'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ahora hay $actual ${actual == 1 ? 'unidad' : 'unidades'}.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            CantidadStepper(
              controller: _ctrl,
              label: 'Nueva cantidad',
              max: widget.max,
              helperText: 'Mínimo 1',
            ),
            const SizedBox(height: 10),
            Text(
              'Si la nueva cantidad es menor, se eliminarán las unidades más '
              'nuevas. Te pediremos confirmación antes de borrar.',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _aplicar,
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}
