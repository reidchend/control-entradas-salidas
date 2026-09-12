import 'package:flutter/material.dart';

import '../../../../core/models/existencia.dart';
import '../../../../core/models/producto.dart';
import '../../../calculadora/presentation/calculadora_button.dart';

/// Fila de un producto de tipo "Consumo" en la vista de descargo masivo.
///
/// Muestra el stock disponible por almacén, el almacén desde el que se
/// descargará (el que tenga más stock, distinto del principal) y un campo de
/// cantidad precargado con esa existencia para poder descargar todo sin editar.
class DescargoConsumibleItem extends StatelessWidget {
  const DescargoConsumibleItem({
    super.key,
    required this.producto,
    required this.existencias,
    required this.almacen,
    required this.controller,
    required this.fmtCant,
  });

  final Producto producto;
  final List<Existencia> existencias;
  final String? almacen;
  final TextEditingController controller;
  final String Function(double) fmtCant;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disponibles = existencias
        .map((e) =>
            '${e.almacen.capitalize()}: ${fmtCant(e.cantidad)} ${e.unidad}')
        .join('  ·  ');
    final estaMarcado =
        (double.tryParse(controller.text.replaceAll(',', '.')) ?? 0) > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: estaMarcado
            ? Border.all(color: scheme.primary, width: 1.4)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(producto.nombre,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
          if (disponibles.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              disponibles,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            Text(
              almacen != null
                  ? 'Descarga desde: ${almacen!.capitalize()}'
                  : 'Sin stock fuera del almacén principal',
              style: TextStyle(
                fontSize: 11,
                color:
                    almacen != null ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: producto.esPesable
                  ? 'Peso a descargar (kg)'
                  : 'Cantidad a descargar',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: CalculadoraSuffixIcon(targetController: controller),
            ),
            keyboardType: TextInputType.numberWithOptions(
                decimal: producto.esPesable),
          ),
        ],
      ),
    );
  }
}

extension _StringCapitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}