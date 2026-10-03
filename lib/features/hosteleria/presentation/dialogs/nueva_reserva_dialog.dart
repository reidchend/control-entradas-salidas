import 'package:flutter/material.dart';

import '../../../../core/models/pos_models.dart';
import '../../data/hosteleria_repository.dart';
import 'checkin_reserva_dialog.dart';

/// Diálogo de nueva reserva (delega en el orquestador de estancia).
/// Retorna `true` si se creó la reserva.
Future<bool> showNuevaReservaDialog(
  BuildContext context, {
  required HosteleriaRepository repo,
  required List<Habitacion> habitaciones,
}) {
  return showCheckinReservaDialog(
    context,
    repo: repo,
    habitaciones: habitaciones,
    modo: CheckinModo.reserva,
  );
}
