/// Tipo de producto del catálogo administrable (`tipos_producto`).
///
/// [rol] es el rol semántico del sistema ('produccion', 'feria', 'venta',
/// 'ninguno'); `null` para tipos libres sin lógica asociada. La lógica de la
/// app pregunta por rol (ver `RolesTipoProducto`), así que el [nombre] de
/// los tipos con rol se puede renombrar sin romper nada — salvo 'ninguno',
/// que además es el default del modelo `Producto`.
///
/// [enUso] es cuántos productos usan el tipo (calculado con un subquery al
/// listar el catálogo).
class TipoProducto {
  const TipoProducto({
    required this.id,
    required this.nombre,
    this.rol,
    this.protegido = false,
    this.activo = true,
    this.orden = 0,
    this.enUso = 0,
  });

  final int id;
  final String nombre;
  final String? rol;
  final bool protegido;
  final bool activo;
  final int orden;
  final int enUso;

  /// El tipo tiene un rol del sistema (no se puede inactivar).
  bool get esDelSistema => rol != null && rol!.isNotEmpty;

  /// Copia con otro nombre (tras renombrar, para refrescar el mapa de roles).
  TipoProducto copyWithNombre(String nombre) => TipoProducto(
        id: id,
        nombre: nombre,
        rol: rol,
        protegido: protegido,
        activo: activo,
        orden: orden,
        enUso: enUso,
      );

  factory TipoProducto.fromMap(Map<String, dynamic> m) => TipoProducto(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        rol: m['rol'] as String?,
        protegido: m['protegido'] == true,
        activo: m['activo'] == true,
        orden: (m['orden'] as num?)?.toInt() ?? 0,
        enUso: (m['en_uso'] as num?)?.toInt() ?? 0,
      );
}
