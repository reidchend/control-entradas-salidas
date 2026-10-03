import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_id_service.dart';
import 'usuarios_repository.dart';
import '../data/postgres_providers.dart';
import '../data/postgres_service.dart';
import '../models/usuario.dart';

/// Sesión del operador de inventario.
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

  UsuariosRepository? get _repo {
    final db = _db;
    return db == null ? null : UsuariosRepository(db);
  }

  static String _pinHash(String pin) =>
      sha256.convert(utf8.encode(pin.trim())).toString();

  /// Registra o re-vincula un operador por nombre+PIN (independiente del
  /// device_id), devolviendo el resultado de la operación.
  Future<bool> registrarOperador({
    required String nombre,
    required String pin,
  }) async {
    final repo = _repo;
    if (repo == null) return false;
    final n = nombre.trim();

    if (await repo.porNombre(n) != null) {
      return verificarPin(nombre: n, pin: pin);
    }

    try {
      // Todo operador que se registra en el módulo administrativo es admin
      // (puede administrar el resto del directorio desde Configuración →
      // Usuarios). Los niveles se ajustan luego desde esa pestaña.
      final id = await repo.crear(
        nombre: n,
        pin: pin,
        nivel: NivelUsuario.admin,
        modulos: {UsuariosRepository.moduloInventario},
      );
      final deviceId = await DeviceIdService.instance.id;
      await repo.vincularDispositivo(id, deviceId);
      state = SessionState.authenticated(
        nombre: n,
        pinHash: _pinHash(pin),
        nivel: NivelUsuario.admin,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verifica nombre+PIN y deja **este dispositivo** asociado a ese operador.
  ///
  /// El PIN se valida (sha256) contra el usuario del directorio central con
  /// acceso al módulo inventario; luego se asocia el dispositivo actual en
  /// `usuario_dispositivos` sin tocar las filas de otros equipos.
  Future<bool> verificarPin({
    required String nombre,
    required String pin,
  }) async {
    final repo = _repo;
    if (repo == null) return false;
    final n = nombre.trim();
    try {
      final u = await repo.porNombre(n);
      if (u == null || !u.activo) return false;
      if (!u.enModulo(UsuariosRepository.moduloInventario)) return false;
      if (!await repo.verificarPin(u, pin)) return false;

      final deviceId = await DeviceIdService.instance.id;
      await repo.vincularDispositivo(u.id, deviceId);
      state = SessionState.authenticated(
        nombre: u.nombre,
        pinHash: u.pinHash ?? _pinHash(pin),
        nivel: u.nivel,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ¿Existe un operador con este nombre con acceso al módulo inventario?
  ///
  /// Da `true` también si el operador está en otro dispositivo: entrar con
  /// nombre+PIN desde uno nuevo debe crear la asociación, no fallar.
  Future<bool> existeOperador(String nombre) async {
    final repo = _repo;
    if (repo == null) return false;
    try {
      return await repo.existeEnModulo(
        nombre.trim(),
        UsuariosRepository.moduloInventario,
      );
    } catch (_) {
      return false;
    }
  }

  /// Nombre del operador vinculado con este device_id, si existe.
  ///
  /// Permite autodetectar el usuario al abrir la app sin reescribirlo.
  Future<String?> nombrePorDeviceId() async {
    final repo = _repo;
    if (repo == null) return null;
    final deviceId = await DeviceIdService.instance.id;
    final u = await repo.porDeviceId(deviceId);
    return u?.nombre;
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
    NivelUsuario nivel,
  }) = Authenticated;
  const factory SessionState.unauthenticated() = Unauthenticated;
}

class Authenticated implements SessionState {
  final String nombre;
  final String pinHash;
  final NivelUsuario nivel;
  const Authenticated({
    required this.nombre,
    required this.pinHash,
    this.nivel = NivelUsuario.basico,
  });

  /// Puede administrar usuarios (ver/editar el directorio central).
  bool get esAdmin =>
      nivel == NivelUsuario.admin || nivel == NivelUsuario.desarrollador;
}

class Unauthenticated implements SessionState {
  const Unauthenticated();
}
