import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_id_service.dart';
import '../data/postgres_providers.dart';
import '../data/postgres_service.dart';

final sessionProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(ref.watch(postgresServiceProvider));
});

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._db) : super(const SessionState.unauthenticated());
  final PostgresService? _db;

  Future<bool> registrarOperador({
    required String nombre,
    required String pin,
  }) async {
    if (_db == null) return false;
    final deviceId = await DeviceIdService.instance.id;
    final result = await _db.insert('dispositivo_usuario', {
      'nombre': nombre,
      'pin_hash': pin,
      'device_id': deviceId,
      'configurado_en': DateTime.now().toIso8601String(),
    });
    state = SessionState.authenticated(nombre: nombre, pinHash: pin);
    return result > 0;
  }

  Future<bool> verificarPin(String pin) async {
    if (_db == null) return false;
    final deviceId = await DeviceIdService.instance.id;
    final rows = await _db.executeSql(
      'SELECT nombre, pin_hash FROM dispositivo_usuario WHERE device_id = \$1 LIMIT 1',
      params: [deviceId],
    );
    if (rows.isEmpty) return false;
    final u = rows.first;
    if (u['pin_hash'] == pin) {
      state = SessionState.authenticated(
        nombre: u['nombre'] as String,
        pinHash: u['pin_hash'] as String,
      );
      return true;
    }
    return false;
  }

  void cerrarSesion() {
    state = const SessionState.unauthenticated();
  }
}

sealed class SessionState {
  const SessionState();
  const factory SessionState.authenticated({
    required String nombre,
    required String pinHash,
  }) = Authenticated;
  const factory SessionState.unauthenticated() = Unauthenticated;
}

class Authenticated implements SessionState {
  final String nombre;
  final String pinHash;
  const Authenticated({required this.nombre, required this.pinHash});
}

class Unauthenticated implements SessionState {
  const Unauthenticated();
}