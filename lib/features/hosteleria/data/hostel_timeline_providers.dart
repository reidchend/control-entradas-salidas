import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/hosteleria_models.dart';
import '../../../core/utils/fecha_utils.dart';
import 'hostel_vista.dart';
import 'hosteleria_providers.dart';

export 'hostel_vista.dart';

/// Vista seleccionada por defecto: estado actual.
final hostelVistaProvider =
    StateProvider<HostelVista>((ref) => HostelVista.actual);

/// Fecha de referencia para las vistas de semana/mes (se normaliza al día).
final hostelAnclaProvider =
    StateProvider<DateTime>((ref) => soloFecha(DateTime.now()));

/// Reservas (incluye finalizadas) dentro de un rango, para la agenda.
final hostelReservasRangoProvider = FutureProvider.autoDispose
    .family<List<HostelReserva>, HostelRango>((ref, rango) async {
  final repo = ref.watch(hosteleriaRepoProvider);
  if (repo == null) return const [];
  return repo.getReservasEnRango(rango.desde, rango.hasta);
});
