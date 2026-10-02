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

  /// Verifica nombre+PIN y deja **este dispositivo** asociado a ese operador.
  ///
  /// Son dos pasos separados a propósito:
  ///
  /// 1. El PIN se valida contra cualquier fila con ese nombre. Si el nombre no
  ///    existe, o el PIN no coincide, no hay sesión.
  /// 2. Recién ahí se resuelve la asociación con el dispositivo: si ya hay una
  ///    fila `(nombre, device_id)` se refresca, y si no se inserta una nueva.
  ///
  /// El paso 2 antes no existía: se buscaba la fila por nombre y se le pisaba el
  /// `device_id` con el del dispositivo actual. Con eso, entrar desde la tablet
  /// **desvinculaba el teléfono**, porque una sola fila guarda un solo
  /// `device_id`. Y como `DeviceIdService` genera el UUID en SharedPreferences,
  /// reinstalar la app generaba otro, así que el enlace se iba con cada
  /// instalación. Ahora un operador puede estar en tantos dispositivos como
  /// haga falta: cada uno tiene su fila y la autodetección los respeta a todos.
  ///
  /// El precio es que cada reinstalación deja la fila anterior atrás. Son filas
  /// inertes (no las devuelve [nombrePorDeviceId] porque su `device_id` ya no
  /// existe en ningún lado) y se pueden borrar a mano.
  Future<bool> verificarPin({
    required String nombre,
    required String pin,
  }) async {
    final db = _db;
    if (db == null) return false;
    final deviceId = await DeviceIdService.instance.id;
    final n = nombre.trim();
    try {
      // 1. Validar el PIN contra el operador.
      final rows = await db.executeSql(
        'SELECT id, nombre, pin_hash FROM dispositivo_usuario '
        'WHERE LOWER(TRIM(nombre)) = LOWER(\$1) ORDER BY id LIMIT 1',
        params: [n],
      );
      if (rows.isEmpty) return false;
      final u = rows.first;
      if (u['pin_hash'] != pin) return false;

      // 2. Asociar ESTE dispositivo, sin tocar las filas de los demás.
      final propias = await db.executeSql(
        'SELECT id FROM dispositivo_usuario '
        'WHERE LOWER(TRIM(nombre)) = LOWER(\$1) AND device_id = \$2 '
        'ORDER BY id LIMIT 1',
        params: [n, deviceId],
      );
      // `configurado_en` es "última vinculación", no "alta": es lo que usa
      // [nombrePorDeviceId] para desempatar cuando el mismo device_id quedó en
      // varias filas.
      if (propias.isEmpty) {
        await db.insert('dispositivo_usuario', {
          'nombre': u['nombre'],
          'pin_hash': pin,
          'device_id': deviceId,
          'configurado_en': DateTime.now().toIso8601String(),
        });
      } else if (propias.first['id'] != null) {
        await db.updateWhere(
          'dispositivo_usuario',
          {'id': propias.first['id']},
          {'configurado_en': DateTime.now().toIso8601String()},
        );
      }
      state = SessionState.authenticated(
        nombre: u['nombre'] as String,
        pinHash: u['pin_hash'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ¿Existe un operador con este nombre en la BD? (case-insensitive).
  ///
  /// Da `true` también si el operador está en otro dispositivo: entrar con
  /// nombre+PIN desde uno nuevo debe crear la asociación, no fallar.
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
