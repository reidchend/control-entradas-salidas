import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/usuarios_providers.dart';
import '../../../core/auth/usuarios_repository.dart';
import '../../../core/data/postgres_providers.dart';
import '../../../core/models/hosteleria_models.dart';
import '../../../core/models/pos_models.dart';
import 'hosteleria_repository.dart';

/// Repositorio compartido del módulo Hostelería.
final hosteleriaRepoProvider = Provider<HosteleriaRepository?>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  return HosteleriaRepository(db);
});

/// Recepcionistas con acceso al módulo Hostelería (login de la app).
final hostelUsuariosProvider =
    FutureProvider.autoDispose<List<Usuario>>((ref) async {
  final repo = ref.watch(usuariosRepoProvider);
  if (repo == null) return const [];
  return repo.listarPorModulo(UsuariosRepository.moduloHosteleria);
});


/// Estado combinado del módulo: habitaciones + reserva activa por habitación.
class HostelEstado {
  const HostelEstado({
    required this.habitaciones,
    required this.reservasActivas,
  });

  final List<Habitacion> habitaciones;
  final List<HostelReserva> reservasActivas;

  Map<int, HostelReserva> get reservasPorHabitacion => {
        for (final r in reservasActivas)
          if (r.ocupaHabitacion) r.habitacionId: r,
      };
}

/// Habitaciones POS (compartidas con el POS) + reservas activas.
final hostelEstadoProvider = FutureProvider.autoDispose<HostelEstado>((ref) async {
  final repo = ref.watch(hosteleriaRepoProvider);
  if (repo == null) return const HostelEstado(habitaciones: [], reservasActivas: []);
  final habs = await repo.getHabitaciones(soloActivas: true);
  final reservas = await repo.getReservas();
  return HostelEstado(
    habitaciones: habs,
    reservasActivas: [
      for (final r in reservas)
        if (r.estado == HostelReservaEstado.reservada ||
            r.estado == HostelReservaEstado.ocupada)
          r,
    ],
  );
});

/// Reservas activas (reservada/ocupada) con datos del huésped.
final hostelReservasActivasProvider =
    FutureProvider.autoDispose<List<HostelReserva>>((ref) async {
  final repo = ref.watch(hosteleriaRepoProvider);
  if (repo == null) return const [];
  final reservas = await repo.getReservas();
  return [
    for (final r in reservas)
      if (r.estado == HostelReservaEstado.reservada ||
          r.estado == HostelReservaEstado.ocupada)
        r,
  ];
});