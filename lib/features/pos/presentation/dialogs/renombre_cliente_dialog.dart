import 'package:flutter/material.dart';

/// Diálogo para poner (o quitar) el nombre personalizado de un cliente.
/// Devuelve el nuevo nombre ya recortado, cadena vacía para quitar el nombre,
/// o `null` si se cancela.
Future<String?> showRenombreClienteDialog(
  BuildContext context, {
  required int numero,
  String? nombreInicial,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _RenombreClienteDialog(
      numero: numero,
      nombreInicial: nombreInicial,
    ),
  );
}

class _RenombreClienteDialog extends StatefulWidget {
  const _RenombreClienteDialog({required this.numero, this.nombreInicial});
  final int numero;
  final String? nombreInicial;

  @override
  State<_RenombreClienteDialog> createState() =>
      _RenombreClienteDialogState();
}

class _RenombreClienteDialogState extends State<_RenombreClienteDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.nombreInicial ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nombre del cliente ${widget.numero}'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Nombre (ej: Ana, Mesa 4, Cuenta 2)',
            hintText: 'Dejar vacío para "Cliente ${widget.numero}"',
            counterText: '',
          ),
          onSubmitted: (_) => Navigator.pop(context, _resultado()),
        ),
      ),
      actions: [
        if (widget.nombreInicial != null)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Quitar nombre'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _resultado()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  String _resultado() => _ctrl.text.trim();
}
