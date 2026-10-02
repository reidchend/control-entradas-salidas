import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_id_service.dart';
import '../data/postgres_providers.dart';
import '../data/postgres_service.dart';

/// Sesión del operador.
///
/// El notifier **no** guarda el `PostgresService` sino una forma de pedirlo en
/// el momento de usarlo. Antes capturaba el valor de `postgresServiceProvider`
/// al construirse, y ese provider devuelve `null` mientras el pool resuelve: el
/// notifier quedaba con una base nula para siempre y todos sus métodos
/// devolvían `false` en silencio. Como el login se monta antes de que el pool
/// esté listo, la autodetección de operador fallaba siempre y había que escribir
/// el nombre a mano en cada arranque.
///
/// Pedirlo por callback además evita que el notifier se reconstruya cuando el
/// pool se invalida (guardar la configuración, tocar "Reintentar"), que antes lo
/// reiniciaba y le cerraba la sesión al operador.
final sessionProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(() => ref.read(postgresServiceProvider));
});

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._resolverDb)
      : super(const SessionState.unauthenticated());
  final PostgresService? Function() _resolverDb;

  /// Base disponible ahora mismo, o `null` si el pool todavía no resolvió o si
  /// no hay configuración.
  PostgresService? get _db => _resolverDb();

  /// Registra o re-vincula un operador por nombre+PIN (independiente del
  /// device_id), devolviendo el resultado de la operación.
  Future<bool> registrarOperador({
    required String nombre,
    required String pin,
  }) async {
    final db = _db;
    if (db == null) return false;
    final deviceId = await DeviceIdService.instance.id;

    if (await existeOperador(nombre)) {
      return verificarPin(nombre: nombre, pin: pin);
    }

    try {
      final result = await db.insert('dispositivo_usuario', {
        'nombre': nombre,
        'pin_hash': pin,
        'device_id': deviceId,
        'configurado_en': DateTime.now().toIso8601String(),
      });
      state = SessionState.authenticated(nombre: nombre, pinHash: pin);
      return result > 0;
    } catch (_) {
      return false;
    }
  }

  /// Verifica nombre+PIN contra la tabla global. Si coincide, actualiza el
  /// device_id de ese operador al dispositivo actual (para que una
  /// reinstalación no vuelva a crear un registro duplicado).
  ///
  /// También refresca `configurado_en`: es lo que usa [nombrePorDeviceId] para
  /// saber con qué operador entró este dispositivo la última vez, así que ese
  /// campo pasó a ser "última vinculación" y no "alta".
  Future<bool> verificarPin({
    required String nombre,
    required String pin,
  }) async {
    final db = _db;
    if (db == null) return false;
    final deviceId = await DeviceIdService.instance.id;
    final n = nombre.trim();
    try {
      final rows = await db.executeSql(
        'SELECT id, nombre, pin_hash FROM dispositivo_usuario '
        'WHERE LOWER(TRIM(nombre)) = LOWER(\$1) ORDER BY id LIMIT 1',
        params: [n],
      );
      if (rows.isEmpty) return false;
      final u = rows.first;
      if (u['pin_hash'] == pin) {
        if (u['id'] != null) {
          await db.updateWhere(
            'dispositivo_usuario',
            {'id': u['id']},
            {
              'device_id': deviceId,
              'configurado_en': DateTime.now().toIso8601String(),
            },
          );
        }
        state = SessionState.authenticated(
          nombre: u['nombre'] as String,
          pinHash: u['pin_hash'] as String,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// ¿Existe un operador con este nombre en la BD? (case-insensitive).
Future<bool> existeOperador(String nombre) async {
    final db = _db;
    if (db == null) return false;
    final n = nombre.trim();
    try {
      final rows = await db.executeSql(
        'SELECT 1 FROM dispositivo_usuario '
        'WHERE LOWER(TRIM(nombre)) = LOWER(\$1) LIMIT 1',
        params: [n],
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Nombre del operador registrado con este device_id, si existe.
  ///
  /// Permite autodetectar el usuario al abrir la app sin reescribirlo.
  ///
  /// Un mismo device_id puede quedar en varias filas (cada reinstalación que
  /// re-vincula el operador deja la anterior atrás), así que se ordena por
  /// `configurado_en` y no por `id`: gana el operador con el que este
  /// dispositivo entró más recientemente, no el más viejo.
  Future<String?> nombrePorDeviceId() async {
    final db = _db;
    if (db == null) return null;
    final deviceId = await DeviceIdService.instance.id;
    final rows = await db.executeSql(
      'SELECT nombre FROM dispositivo_usuario '
      'WHERE device_id = \$1 ORDER BY configurado_en DESC, id DESC LIMIT 1',
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
