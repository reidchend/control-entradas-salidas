import 'package:flutter/material.dart';

import '../../../../core/models/producto.dart';

/// Diálogo de ajuste de conteo físico (porta `build_ajuste_dialog`).
/// Devuelve `(nuevaCantidad, motivo)` o `null` si se cancela.
Future<(double, String)?> showAjusteDialog(
  BuildContext context, {
  required Producto producto,
  required String almacen,
  required double cantidadActual,
}) async {
  final esPesable = producto.esPesable;
  final cantCtrl = TextEditingController(
    text: esPesable
        ? cantidadActual.toStringAsFixed(3)
        : cantidadActual.round().toString(),
  );
  final motivoCtrl = TextEditingController();
  final unidad = producto.unidadMedida.isEmpty ? 'uds' : producto.unidadMedida;

  String? errorText;

  return await showDialog<(double, String)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: Text('Ajustar: ${almacen.capitalize()}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock actual: ${esPesable ? cantidadActual.toStringAsFixed(3) : cantidadActual.round()} $unidad',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const Divider(height: 16),
              TextField(
                controller: cantCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  labelText: 'Nuevo conteo físico',
                  suffixText: unidad,
                  errorText: errorText,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: motivoCtrl,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final valor = double.tryParse(
                  cantCtrl.text.replaceAll(',', '').replaceAll(' ', ''));
              if (valor == null || valor < 0) {
                setSt(() => errorText = 'Número válido ≥ 0');
                return;
              }
              Navigator.pop(ctx, (valor, motivoCtrl.text.trim()));
            },
            child: const Text('Confirmar ajuste'),
          ),
        ],
      ),
    ),
  );
}

extension _StringCapitalize on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
