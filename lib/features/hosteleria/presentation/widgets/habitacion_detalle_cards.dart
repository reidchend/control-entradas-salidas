/// Tarjetas de detalle de una habitación: estado de la estancia o estado
/// operativo. Comparten el mismo código de colores que el grid.
library;

import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../../../../core/models/pos_models.dart';
import 'habitacion_estado.dart';

class ReservaDetalleCard extends StatelessWidget {
  const ReservaDetalleCard({
    super.key,
    required this.habitacion,
    required this.reserva,
  });

  final Habitacion habitacion;
  final HostelReserva reserva;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = estadoVisualHabitacion(context, habitacion, reserva);
    final restantes = reserva.minutosRestantes();
    final vencida = restantes != null && restantes < 0;
    final timerColor = vencida ? scheme.error : visual.color;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: visual.color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.meeting_room_outlined,
                  size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Habitación ${habitacion.numero}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              _Chip(label: visual.label, color: visual.color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              habitacion.piso,
              habitacion.tipo,
              'cap. ${habitacion.maxPersonas}',
            ].whereType<String>().join(' · '),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if ((reserva.huespedNombre ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.person_outline,
                      size: 20, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Huésped',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant)),
                      Text(
                        reserva.huespedNombre!.trim(),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _Dato(
            icon: Icons.timer_outlined,
            titulo: 'Modalidad',
            valor: reserva.modalidadLabel,
          ),
          _Dato(
            icon: Icons.event_available_outlined,
            titulo: 'Entrada',
            valor: _fecha(reserva.fechaIngreso),
          ),
          if (!reserva.esPorHoras)
            _Dato(
              icon: Icons.event_busy_outlined,
              titulo: 'Salida',
              valor: _fecha(reserva.fechaSalida),
            ),
          if (reserva.horaEntrada != null)
            _Dato(
              icon: Icons.login,
              titulo: 'Check-in real',
              valor: _hora(reserva.horaEntrada!),
            ),
          if (reserva.horaSalida != null)
            _Dato(
              icon: Icons.logout,
              titulo: 'Check-out real',
              valor: _hora(reserva.horaSalida!),
            ),
          if (reserva.estado == HostelReservaEstado.ocupada &&
              reserva.esPorHoras &&
              restantes != null) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: timerColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: timerColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(
                    vencida ? Icons.warning_amber_outlined : Icons.schedule,
                    size: 18,
                    color: timerColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      vencida
                          ? 'OP vencida hace ${-restantes} min'
                          : 'OP · $restantes min restantes',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: timerColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EstadoDetalleCard extends StatelessWidget {
  const EstadoDetalleCard({super.key, required this.habitacion});

  final Habitacion habitacion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = estadoVisualHabitacion(context, habitacion, null);
    final icon = switch (habitacion.estado) {
      EstadoHabitacion.aseo => Icons.cleaning_services_outlined,
      EstadoHabitacion.mantenimiento => Icons.build_outlined,
      _ => Icons.check_circle_outline,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: visual.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: visual.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visual.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                if ((habitacion.estadoNotas ?? '').isNotEmpty)
                  Text(
                    habitacion.estadoNotas!,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icon, required this.titulo, required this.valor});

  final IconData icon;
  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
                Text(valor,
                    style: TextStyle(fontSize: 13, color: scheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _fecha(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _hora(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
