import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/usuarios_providers.dart';
import '../../../core/auth/usuarios_repository.dart';
import '../../../core/data/postgres_providers.dart';
import '../../../core/models/hosteleria_models.dart';
import '../../../core/models/pos_models.dart';
import '../../../core/models/usuario.dart';
import 'hostel_db_backend.dart';
import 'hostel_db_notifier.dart';
import 'hostel_postgres_backend.dart';
import 'hostel_sqlite_init.dart';
import 'hosteleria_repository.dart';

/// Verifica un PIN contra un hash SHA-256 almacenado localmente.
bool verificarPinLocal(String pin, String? pinHash) {
  if (pinHash == null || pinHash.isEmpty) return true; // sin contraseña
  final hash = sha256.convert(utf8.encode(pin.trim())).toString();
  return hash == pinHash;
}

/// Repositorio compartido del módulo Hostelería.
///
/// Expone el repositorio de forma síncrona gracias a [hostelDbBackendProvider]
/// (StateNotifier). Si el backend aún no se inicializó o falló, devuelve null.
final hosteleriaRepoProvider = Provider<HosteleriaRepository?>((ref) {
  final backend = ref.watch(hostelDbBackendProvider);
  if (backend == null) return null;
  return HosteleriaRepository(backend);
});

/// Indica si el módulo está usando SQLite local (modo pruebas) en vez de
/// PostgreSQL (producción). Útil para mostrar un indicador visual al usuario.
final hostelModoPruebasProvider = Provider<bool>((ref) {
  final backend = ref.watch(hostelDbBackendProvider);
  // Si el backend es PostgresDbBackend, no es modo pruebas. De lo contrario,
  // asumimos SQLite (modo pruebas).
  return backend is! PostgresDbBackend;
});

/// Usuarios de recepción leídos desde SQLite local (modo pruebas sin Postgres).
final hostelUsuariosSqliteProvider =
    FutureProvider.autoDispose<List<Usuario>>((ref) async {
  final backend = ref.watch(hostelDbBackendProvider);
  if (backend == null) return const [];
  final filas = await backend.executeSql(
    'SELECT * FROM hosteleria_usuarios WHERE activo = 1 ORDER BY nombre',
  );
  return [
    for (final f in filas)
      Usuario(
        id: f['id'] as int,
        nombre: f['nombre'] as String,
        pinHash: f['pin_hash'] as String?,
        nivel: (f['es_admin'] as int?) == 1
            ? NivelUsuario.admin
            : NivelUsuario.basico,
        activo: true,
        modulos: const {'hosteleria'},
      ),
  ];
});

/// Recepcionistas con acceso al módulo Hostelería (login de la app).
final hostelUsuariosProvider =
    FutureProvider.autoDispose<List<Usuario>>((ref) async {
  final repo = ref.watch(usuariosRepoProvider);
  if (repo != null) {
    return repo.listarPorModulo(UsuariosRepository.moduloHosteleria);
  }
  return await ref.read(hostelUsuariosSqliteProvider.future);
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
