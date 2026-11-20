/// Traduce el estado operativo/reserva de una habitación a etiqueta y color.
///
/// Se mantiene fuera del grid para que la regla de prioridad de estados sea
/// única y fácil de ajustar:
///   reservada (naranja) → OP por horas (azul claro) → ocupada (verde)
///   → aseo (morado) → mantenimiento (gris) → disponible (morado theme).
library;

import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../../../../core/models/pos_models.dart';
import '../../../../core/theme/app_theme.dart';

({String label, Color color, int? minutosRestantes}) estadoVisualHabitacion(
  BuildContext context,
  Habitacion habitacion,
  HostelReserva? reserva,
) {
  final scheme = Theme.of(context).colorScheme;

  if (reserva != null &&
      reserva.estado == HostelReservaEstado.reservada) {
    return (
      label: 'Reservada',
      color: appColor(context, 'warning'),
      minutosRestantes: null,
    );
  }

  if (reserva != null && reserva.estado == HostelReservaEstado.ocupada) {
    final esOp = reserva.esPorHoras;
    return (
      label: esOp ? 'OP' : 'Ocupada',
      color: appColor(context, esOp ? 'light_blue' : 'success'),
      minutosRestantes: reserva.minutosRestantes(),
    );
  }

  return switch (habitacion.estado) {
    EstadoHabitacion.aseo => (
        label: 'Aseo',
        color: appColor(context, 'accent_dark'),
        minutosRestantes: null,
      ),
    EstadoHabitacion.mantenimiento => (
        label: 'Mantenimiento',
        color: scheme.onSurfaceVariant,
        minutosRestantes: null,
      ),
    _ => (
        label: 'Disponible',
        color: scheme.primary,
        minutosRestantes: null,
      ),
  };
}
