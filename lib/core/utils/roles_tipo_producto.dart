import '../models/tipo_producto.dart';

/// Resuelve capacidades de un tipo de producto por su nombre actual,
/// independiente del texto editable.
///
/// Dos preguntas, ambas refrescadas desde el catálogo (`tipos_producto`):
///
/// - **Rol** ('produccion', 'feria', 'venta', 'ninguno'): liga los flujos
///   del sistema (producción, colores), así que el nombre de los tipos con
///   rol se puede renombrar sin romper nada.
/// - **Puede ser ingrediente** (`es_insumo`): regla de negocio del POS
///   (se descarga del inventario al vender el plato).
///
/// El mapa se refresca al arrancar la app, al abrir Configuración, al abrir
/// el diálogo de producto y al abrir el diálogo de platos del POS; si
/// todavía no cargó, cae a la equivalencia histórica por texto.
class RolesTipoProducto {
  RolesTipoProducto._();

  /// Roles reservados del sistema.
  static const String produccion = 'produccion';
  static const String feria = 'feria';
  static const String venta = 'venta';
  static const String ninguno = 'ninguno';

  static Map<String, String> _rolPorNombre = const {};
  static Map<String, bool> _esInsumoPorNombre = const {};

  /// Refresca los mapas con el catálogo vivo (los nombres cambian al
  /// renombrar). Hace MERGE sobre lo ya cargado: una llamada con una lista
  /// parcial (p. ej. solo el tipo recién renombrado) no debe vaciar el
  /// resto de los roles ya conocidos.
  static void actualizar(Iterable<TipoProducto> catalogo) {
    _rolPorNombre = {
      ..._rolPorNombre,
      for (final t in catalogo)
        if (t.rol != null && t.rol!.isNotEmpty) t.nombre: t.rol!,
    };
    _esInsumoPorNombre = {
      ..._esInsumoPorNombre,
      for (final t in catalogo) t.nombre: t.esInsumo,
    };
  }

  /// Rol de un tipo por su nombre actual. Cadena vacía si es un tipo libre
  /// (sin lógica asociada).
  static String rolDe(String? tipo) {
    final nombre = (tipo ?? '').trim();
    if (nombre.isEmpty) return ninguno;
    final rol = _rolPorNombre[nombre];
    if (rol != null && rol.isNotEmpty) return rol;
    return _rolHistorico(nombre);
  }

  /// ¿Los productos de este tipo pueden usarse como ingrediente de platos
  /// del POS? Regla administrada en Configuración > Tipos (`es_insumo`).
  static bool puedeSerIngrediente(String? tipo) {
    final nombre = (tipo ?? '').trim();
    final marcado = _esInsumoPorNombre[nombre];
    if (marcado != null) return marcado;
    if (nombre.isEmpty) return false;
    // Fallback pre-catálogo: la regla de negocio por su texto histórico.
    final rol = _rolHistorico(nombre);
    if (rol == produccion || rol == feria) return true;
    return nombre.toLowerCase().contains('uso interno');
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
