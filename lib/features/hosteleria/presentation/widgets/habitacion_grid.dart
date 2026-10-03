import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../../../../core/models/pos_models.dart';

/// Grid de habitaciones con estado ocupada/reservada/aseo/mantenimiento.
class HabitacionGrid extends StatefulWidget {
  const HabitacionGrid({
    super.key,
    required this.habitaciones,
    required this.reservasPorHabitacion,
    required this.onTap,
  });

  final List<Habitacion> habitaciones;
  final Map<int, HostelReserva> reservasPorHabitacion;
  final ValueChanged<Habitacion> onTap;

  @override
  State<HabitacionGrid> createState() => _HabitacionGridState();
}

class _HabitacionGridState extends State<HabitacionGrid> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(minutes: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GridView.extent(
      padding: const EdgeInsets.all(16),
      maxCrossAxisExtent: 150,
      childAspectRatio: 0.9,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: [
        for (final hab in widget.habitaciones)
          _HabitacionTile(
            habitacion: hab,
            reserva: widget.reservasPorHabitacion[hab.id],
            onTap: () => widget.onTap(hab),
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

  final Habitacion habitacion;
  final HostelReserva? reserva;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reservada =
        reserva != null && reserva!.estado == HostelReservaEstado.reservada;
    final ocupada = reserva != null &&
        reserva!.estado == HostelReservaEstado.ocupada;
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = ocupada
        ? ('Ocupada', scheme.error)
        : reservada
            ? ('Reservada', scheme.tertiary)
            : switch (habitacion.estado) {
                EstadoHabitacion.aseo => ('Aseo', Colors.orange),
                EstadoHabitacion.mantenimiento =>
                  ('Mantenimiento', Colors.blueGrey),
                _ => ('Disponible', scheme.primary),
              };
    final restantes = ocupada ? reserva!.minutosRestantes() : null;
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
                label,
                style: TextStyle(fontSize: 12, color: color),
              ),
              if (restantes != null) ...[
                const SizedBox(height: 2),
                Text(
                  restantes < 0 ? 'OP vencida' : 'OP · $restantes min',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: restantes < 0 ? scheme.error : Colors.orange,
                  ),
                ),
              ],
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
