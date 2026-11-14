import 'package:flutter/material.dart';

/// Encabezado compacto de la comanda activa.
///
/// Muestra "Mesa X · Particular" o "Mesa X · Hab 101 · Hab 103".
/// Está diseñado para tablets pequeñas en horizontal: ocupa poco ancho y usa
/// solo colores del tema (claro/oscuro).
class ComandaEncabezado extends StatelessWidget {
  const ComandaEncabezado({
    super.key,
    required this.mesaNumero,
    this.habitaciones, // null | 'Particular' | '101, 103'
  });

  final int mesaNumero;
  final String? habitaciones;

  bool get _esParticular => habitaciones == 'Particular';
  List<String> get _listaHabitaciones {
    if (_esParticular || habitaciones == null || habitaciones!.isEmpty) {
      return <String>[];
    }
    return habitaciones!
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_restaurant, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            'Mesa $mesaNumero',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (_esParticular) ...[
            const SizedBox(width: 8),
            Chip(
              label: const Text('Particular'),
              backgroundColor: scheme.surfaceContainerHighest,
              labelStyle: const TextStyle(fontSize: 12),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ] else if (_listaHabitaciones.isNotEmpty) ...[
            const SizedBox(width: 8),
            for (final h in _listaHabitaciones) ...[
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Hab $h',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
