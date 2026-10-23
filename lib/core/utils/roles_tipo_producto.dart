import '../models/tipo_producto.dart';

/// Rol semántico de un tipo de producto, independiente del nombre editable.
///
/// La lógica de la app (flujo de producción en el alta de entradas, colores
/// del tipo en las cards) pregunta por ROL ('produccion', 'feria', 'venta',
/// 'ninguno'), no por el texto: los tipos del sistema se pueden renombrar
/// desde Configuración > Tipos sin romper nada.
///
/// El mapa nombre→rol se refresca desde el catálogo (`tipos_producto.rol`)
/// al arrancar la app, al abrir Configuración y al listar tipos en Stock; si
/// todavía no cargó, cae a la equivalencia histórica por texto (la misma que
/// usaba la app antes del catálogo).
class RolesTipoProducto {
  RolesTipoProducto._();

  /// Roles reservados del sistema.
  static const String produccion = 'produccion';
  static const String feria = 'feria';
  static const String venta = 'venta';
  static const String ninguno = 'ninguno';

  static Map<String, String> _porNombre = const {};

  /// Refresca el mapa con el catálogo vivo (los nombres cambian al renombrar).
  static void actualizar(Iterable<TipoProducto> catalogo) {
    _porNombre = {
      for (final t in catalogo)
        if (t.rol != null && t.rol!.isNotEmpty) t.nombre: t.rol!,
    };
  }

  /// Rol de un tipo por su nombre actual. Cadena vacía si es un tipo libre
  /// (sin lógica asociada).
  static String rolDe(String? tipo) {
    final nombre = (tipo ?? '').trim();
    if (nombre.isEmpty) return ninguno;
    final rol = _porNombre[nombre];
    if (rol != null && rol.isNotEmpty) return rol;
    return _rolHistorico(nombre);
  }

  /// Equivalencia por texto usada antes del catálogo: cubre el arranque en
  /// frío (el mapa se llena unos ms después) y coincide con los nombres
  /// históricos de la BD.
  static String _rolHistorico(String nombre) {
    final l = nombre.toLowerCase();
    if (l == 'ninguno') return ninguno;
    if (l == 'feria') return feria;
    if (l.contains('producci')) return produccion;
    if (l.contains('venta')) return venta;
    return '';
  }
}
