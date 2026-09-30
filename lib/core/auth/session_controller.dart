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

  /// Registra o re-vincula un operador por nombre+PIN (independiente del
  /// device_id), devolviendo el resultado de la operación.
  Future<bool> registrarOperador({
    required String nombre,
    required String pin,
  }) async {
    if (_db == null) return false;
    final deviceId = await DeviceIdService.instance.id;
    print('[SESSION] registrarOperador: nombre="$nombre", deviceId=$deviceId');

    if (await existeOperador(nombre)) {
      print('[SESSION] registrarOperador: usuario ya existe, verificando PIN');
      return verificarPin(nombre: nombre, pin: pin);
    }

    try {
      final result = await _db.insert('dispositivo_usuario', {
        'nombre': nombre,
        'pin_hash': pin,
        'device_id': deviceId,
        'configurado_en': DateTime.now().toIso8601String(),
      });
      print('[SESSION] registrarOperador: insert result=$result');
      state = SessionState.authenticated(nombre: nombre, pinHash: pin);
      return result > 0;
    } catch (e, st) {
      print('[SESSION] registrarOperador ERROR: $e');
      print('[SESSION] registrarOperador STACK: $st');
      return false;
    }
  }

  /// Verifica nombre+PIN contra la tabla global. Si coincide, actualiza el
  /// device_id de ese operador al dispositivo actual (para que una
  /// reinstalación no vuelva a crear un registro duplicado).
  Future<bool> verificarPin({
    required String nombre,
    required String pin,
  }) async {
    if (_db == null) return false;
    final deviceId = await DeviceIdService.instance.id;
    final n = nombre.trim();
    print('[SESSION] verificarPin: nombre="$n", pin="$pin", deviceId=$deviceId');
    try {
      final rows = await _db.executeSql(
        'SELECT id, nombre, pin_hash FROM dispositivo_usuario '
        'WHERE LOWER(TRIM(nombre)) = LOWER(\$1) ORDER BY id LIMIT 1',
        params: [n],
      );
      print('[SESSION] verificarPin: rows=${rows.length} for "$n"');
      if (rows.isEmpty) return false;
      final u = rows.first;
      print('[SESSION] verificarPin: found id=${u['id']}, nombre=${u['nombre']}, pin_hash=${u['pin_hash']}');
      if (u['pin_hash'] == pin) {
        if (u['id'] != null) {
          await _db.updateWhere(
            'dispositivo_usuario',
            {'id': u['id']},
            {'device_id': deviceId},
          );
        }
        state = SessionState.authenticated(
          nombre: u['nombre'] as String,
          pinHash: u['pin_hash'] as String,
        );
        return true;
      }
      print('[SESSION] verificarPin: PIN mismatch, expected=${u['pin_hash']}, got=$pin');
      return false;
    } catch (e, st) {
      print('[SESSION] verificarPin ERROR: $e');
      print('[SESSION] verificarPin STACK: $st');
      return false;
    }
  }

  /// ¿Existe un operador con este nombre en la BD? (case-insensitive).
Future<bool> existeOperador(String nombre) async {
    if (_db == null) return false;
    final n = nombre.trim();
    print('[SESSION] existeOperador: nombre="$n"');
    try {
      final rows = await _db.executeSql(
        'SELECT 1 FROM dispositivo_usuario '
        'WHERE LOWER(TRIM(nombre)) = LOWER($1) LIMIT 1',
        params: [n],
      );
      print('[SESSION] existeOperador: rows=${rows.length} for "$n"');
      return rows.isNotEmpty;
    } catch (e, st) {
      print('[SESSION] existeOperador ERROR: $e');
      print('[SESSION] existeOperador STACK: $st');
      return false;
    }
  }

  /// Nombre del operador registrado con este device_id, si existe.
  /// Permite autodetectar el usuario al abrir la app sin reescribirlo.
  Future<String?> nombrePorDeviceId() async {
    if (_db == null) return null;
    final deviceId = await DeviceIdService.instance.id;
    final rows = await _db.executeSql(
      'SELECT nombre FROM dispositivo_usuario '
      'WHERE device_id = \$1 ORDER BY id LIMIT 1',
      params: [deviceId],
    );
    if (rows.isEmpty) return null;
    return rows.first['nombre'] as String?;
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