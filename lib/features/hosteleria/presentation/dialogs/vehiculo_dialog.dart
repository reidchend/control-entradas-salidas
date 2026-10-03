import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';

/// Diálogo para capturar/editar un vehículo de la estancia (placa + modelo).
/// Retorna el [HostelVehiculoInput] aceptado o `null` si se cancela.
Future<HostelVehiculoInput?> showVehiculoDialog(
  BuildContext context, {
  HostelVehiculoInput? inicial,
}) {
  return showDialog<HostelVehiculoInput>(
    context: context,
    builder: (_) => _VehiculoDialog(inicial: inicial),
  );
}

class _VehiculoDialog extends StatefulWidget {
  const _VehiculoDialog({this.inicial});

  final HostelVehiculoInput? inicial;

  @override
  State<_VehiculoDialog> createState() => _VehiculoDialogState();
}

class _VehiculoDialogState extends State<_VehiculoDialog> {
  late final TextEditingController _placa;
  late final TextEditingController _modelo;
  String? _error;

  @override
  void initState() {
    super.initState();
    _placa = TextEditingController(text: widget.inicial?.placa ?? '');
    _modelo = TextEditingController(text: widget.inicial?.modelo ?? '');
  }

  @override
  void dispose() {
    _placa.dispose();
    _modelo.dispose();
    super.dispose();
  }

  void _aceptar() {
    final placa = _placa.text.trim();
    if (placa.isEmpty) {
      setState(() => _error = 'Ingrese la placa del vehículo.');
      return;
    }
    Navigator.pop(
      context,
      HostelVehiculoInput(placa: placa, modelo: _modelo.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vehículo'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _placa,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Placa *',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelo,
              decoration: const InputDecoration(
                labelText: 'Modelo (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
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
