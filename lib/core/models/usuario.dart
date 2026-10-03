/// Nivel global de privilegios de un usuario del sistema.
///
/// - [basico]: usa el módulo (cajero, recepcionista, operador de inventario).
/// - [admin]: además entra a las configuraciones del módulo y crea/edita.
/// - [desarrollador]: acceso global a todos los módulos (ver [Usuario.enModulo]).
enum NivelUsuario {
  basico,
  admin,
  desarrollador;

  static NivelUsuario fromDb(String? valor) => switch (valor) {
        'admin' => NivelUsuario.admin,
        'desarrollador' => NivelUsuario.desarrollador,
        _ => NivelUsuario.basico,
      };

  String get db => name;
}

/// Usuario del directorio central (`usuarios`), compartido por inventario,
/// POS y hostelería.
///
/// El acceso a cada app se resuelve con [modulos] (tabla `usuario_modulos`);
/// un [NivelUsuario.desarrollador] entra a todos los módulos sin importar la
/// membresía. El alta/edición se hace desde la administración (aún pendiente).
class Usuario {
  const Usuario({
    required this.id,
    required this.nombre,
    this.pinHash,
    this.nivel = NivelUsuario.basico,
    this.activo = true,
    this.modulos = const {},
    this.creadoEn,
    this.updatedAt,
  });

  final int id;
  final String nombre;
  final String? pinHash;
  final NivelUsuario nivel;
  final bool activo;
  final Set<String> modulos;
  final String? creadoEn;
  final DateTime? updatedAt;

  bool get esDesarrollador => nivel == NivelUsuario.desarrollador;
  bool get esAdmin => nivel == NivelUsuario.admin || esDesarrollador;
  bool get esBasico => nivel == NivelUsuario.basico;

  /// ¿Puede entrar al [modulo]? El desarrollador entra a todos.
  bool enModulo(String modulo) => esDesarrollador || modulos.contains(modulo);

  factory Usuario.fromMap(Map<String, dynamic> m) => Usuario(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        pinHash: m['pin_hash'] as String?,
        nivel: NivelUsuario.fromDb(m['nivel'] as String?),
        activo: (m['activo'] as int?) == 1,
        modulos: _parseModulos(m['modulos']),
        creadoEn: m['creado_en'] as String?,
        updatedAt: _parseDt(m['updated_at']),
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'nombre': nombre,
        'pin_hash': pinHash,
        'nivel': nivel.db,
        'activo': activo ? 1 : 0,
        'creado_en': creadoEn,
      };

  static Set<String> _parseModulos(dynamic v) {
    if (v == null) return const {};
    if (v is List) return {for (final e in v) '$e'};
    return {'$v'};
  }

  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
