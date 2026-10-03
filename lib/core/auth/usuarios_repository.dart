import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/postgres_service.dart';
import '../models/usuario.dart';

/// Acceso al directorio central de usuarios (`usuarios` + `usuario_modulos` +
/// `usuario_dispositivos`). Lo comparten inventario, POS y hostelería.
class UsuariosRepository {
  UsuariosRepository(this._db);

  final PostgresService _db;

  static const String moduloInventario = 'inventario';
  static const String moduloPos = 'pos';
  static const String moduloHosteleria = 'hosteleria';

  static String _pinHash(String pin) =>
      sha256.convert(utf8.encode(pin.trim())).toString();

  static const String _selectUsuario = '''
    SELECT u.*,
           COALESCE(array_agg(m.modulo)
             FILTER (WHERE m.modulo IS NOT NULL), '{}') AS modulos
      FROM usuarios u
      LEFT JOIN usuario_modulos m ON m.usuario_id = u.id
  ''';

  Future<List<Usuario>> listarPorModulo(
    String modulo, {
    bool soloActivos = true,
  }) async {
    final rows = await _db.executeSql(
      '$_selectUsuario'
      ' WHERE u.id IN (SELECT usuario_id FROM usuario_modulos WHERE modulo = \$1)'
      '${soloActivos ? ' AND u.activo = 1' : ''}'
      ' GROUP BY u.id ORDER BY u.nombre',
      params: [modulo],
    );
    return rows.map(Usuario.fromMap).toList();
  }

  Future<Usuario?> porId(int id) async {
    final rows = await _db.executeSql(
      '$_selectUsuario WHERE u.id = \$1 GROUP BY u.id LIMIT 1',
      params: [id],
    );
    return rows.isEmpty ? null : Usuario.fromMap(rows.first);
  }

  Future<Usuario?> porNombre(String nombre) async {
    final rows = await _db.executeSql(
      '$_selectUsuario'
      ' WHERE LOWER(TRIM(u.nombre)) = LOWER(TRIM(\$1))'
      ' GROUP BY u.id ORDER BY u.id LIMIT 1',
      params: [nombre],
    );
    return rows.isEmpty ? null : Usuario.fromMap(rows.first);
  }

  /// ¿Existe un usuario con este nombre con acceso al [modulo]?
  Future<bool> existeEnModulo(String nombre, String modulo) async {
    final rows = await _db.executeSql(
      'SELECT 1 FROM usuarios u'
      ' JOIN usuario_modulos m ON m.usuario_id = u.id'
      ' WHERE LOWER(TRIM(u.nombre)) = LOWER(TRIM(\$1))'
      ' AND (m.modulo = \$2 OR u.nivel = \'desarrollador\') LIMIT 1',
      params: [nombre, modulo],
    );
    return rows.isNotEmpty;
  }

  /// Valida el PIN (sha256) del usuario. Devuelve `true` si el usuario no
  /// tiene PIN configurado.
  Future<bool> verificarPin(Usuario usuario, String pin) async {
    final hash = usuario.pinHash;
    if (hash == null || hash.isEmpty) return true;
    return hash == _pinHash(pin);
  }

  /// Usuario vinculado a [deviceId] para el auto-login. Si el equipo quedó en
  /// varias filas (re-vinculaciones), gana la más reciente.
  Future<Usuario?> porDeviceId(String deviceId) async {
    final rows = await _db.executeSql(
      '$_selectUsuario'
      ' JOIN usuario_dispositivos d ON d.usuario_id = u.id'
      ' WHERE d.device_id = \$1 AND u.activo = 1'
      ' GROUP BY u.id, d.configurado_en, d.id'
      ' ORDER BY d.configurado_en DESC NULLS LAST, d.id DESC LIMIT 1',
      params: [deviceId],
    );
    return rows.isEmpty ? null : Usuario.fromMap(rows.first);
  }

  Future<void> vincularDispositivo(int usuarioId, String deviceId) async {
    await _db.executeCommand(
      'INSERT INTO usuario_dispositivos (usuario_id, device_id, configurado_en)'
      ' VALUES (\$1, \$2, \$3)'
      ' ON CONFLICT (usuario_id, device_id)'
      ' DO UPDATE SET configurado_en = EXCLUDED.configurado_en',
      params: [usuarioId, deviceId, DateTime.now().toIso8601String()],
    );
  }

  Future<void> desvincularDispositivo(String deviceId) async {
    await _db.executeCommand(
      'DELETE FROM usuario_dispositivos WHERE device_id = \$1',
      params: [deviceId],
    );
  }

  Future<int> crear({
    required String nombre,
    String? pin,
    NivelUsuario nivel = NivelUsuario.basico,
    Set<String> modulos = const {},
  }) async {
    final id = await _db.insert('usuarios', {
      'nombre': nombre.trim(),
      'pin_hash': (pin != null && pin.trim().isNotEmpty) ? _pinHash(pin) : null,
      'nivel': nivel.db,
      'activo': 1,
      'creado_en': DateTime.now().toIso8601String(),
    });
    await _setModulos(id, modulos);
    return id;
  }

  Future<void> actualizar(
    int id, {
    String? nombre,
    String? pin,
    NivelUsuario? nivel,
    bool? activo,
    Set<String>? modulos,
  }) async {
    final data = <String, dynamic>{
      if (nombre != null) 'nombre': nombre.trim(),
      if (nivel != null) 'nivel': nivel.db,
      if (activo != null) 'activo': activo ? 1 : 0,
      if (pin != null) 'pin_hash': pin.isEmpty ? null : _pinHash(pin),
    };
    if (data.isNotEmpty) {
      await _db.updateById('usuarios', id, data);
    }
    if (modulos != null) {
      await _setModulos(id, modulos);
    }
  }

  Future<void> _setModulos(int usuarioId, Set<String> modulos) async {
    await _db.executeCommand(
      'DELETE FROM usuario_modulos WHERE usuario_id = \$1',
      params: [usuarioId],
    );
    for (final modulo in modulos) {
      await _db.executeCommand(
        'INSERT INTO usuario_modulos (usuario_id, modulo) VALUES (\$1, \$2)'
        ' ON CONFLICT DO NOTHING',
        params: [usuarioId, modulo],
      );
    }
  }

  /// Asegura la membresía de un usuario a un módulo sin tocar las demás.
  Future<void> agregarModulo(int usuarioId, String modulo) async {
    await _db.executeCommand(
      'INSERT INTO usuario_modulos (usuario_id, modulo) VALUES (\$1, \$2)'
      ' ON CONFLICT DO NOTHING',
      params: [usuarioId, modulo],
    );
  }
}
