import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Campo numérico con botones − y + para elegir una cantidad.
///
/// Se usa en el alta (cuántas unidades iguales se crean) y en los diálogos de
/// cantidad/mover. El texto sigue siendo editable para escribir directamente
/// cantidades grandes sin tocar el + muchas veces.
class CantidadStepper extends StatelessWidget {
  const CantidadStepper({
    super.key,
    required this.controller,
    this.label = 'Cantidad',
    this.min = 1,
    this.max = 500,
    this.helperText,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final int min;
  final int max;
  final String? helperText;
  final bool enabled;

  int get _valor {
    final n = int.tryParse(controller.text.trim());
    return (n ?? min).clamp(min, max);
  }

  void _fijar(int v) => controller.text = v.clamp(min, max).toString();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: label,
              helperText: helperText,
            ),
            onChanged: (text) {
              final n = int.tryParse(text);
              if (n != null && n > max) _fijar(max);
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Quitar una',
          onPressed: enabled && _valor > min ? () => _fijar(_valor - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: 2),
        IconButton.filledTonal(
          tooltip: 'Agregar una',
          onPressed: enabled && _valor < max ? () => _fijar(_valor + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
