import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../../../../core/models/pos_models.dart';

/// Grid de habitaciones con estado ocupada/reservada/disponible.
class HabitacionGrid extends StatelessWidget {
  const HabitacionGrid({
    super.key,
    required this.habitaciones,
    required this.reservasPorHabitacion,
    required this.onTap,
  });

  final List<PosHabitacion> habitaciones;
  final Map<int, HostelReserva> reservasPorHabitacion;
  final ValueChanged<PosHabitacion> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.extent(
      padding: const EdgeInsets.all(16),
      maxCrossAxisExtent: 150,
      childAspectRatio: 0.9,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: [
        for (final hab in habitaciones)
          _HabitacionTile(
            habitacion: hab,
            reserva: reservasPorHabitacion[hab.id],
            onTap: () => onTap(hab),
          ),
      ],
    );
  }
}

class _HabitacionTile extends StatelessWidget {
  const _HabitacionTile({
    required this.habitacion,
    required this.reserva,
    required this.onTap,
  });

  final PosHabitacion habitacion;
  final HostelReserva? reserva;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reservada =
        reserva != null && reserva!.estado == HostelReservaEstado.reservada;
    final ocupada = reserva != null &&
        reserva!.estado == HostelReservaEstado.ocupada;
    final color = ocupada
        ? Theme.of(context).colorScheme.error
        : reservada
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.primary;
    final info = [habitacion.piso, habitacion.tipo]
        .whereType<String>()
        .join(' · ');

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'HAB ${habitacion.numero}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                ocupada
                    ? 'Ocupada'
                    : reservada
                        ? 'Reservada'
                        : 'Disponible',
                style: TextStyle(fontSize: 12, color: color),
              ),
              if (info.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(info.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}