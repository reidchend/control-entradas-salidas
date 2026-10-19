import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import '../../../core/models/almacen.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/proveedor.dart';
import '../../../core/models/periodo.dart';
import 'configuracion_repository.dart';

/// Provider compartido del repositorio de configuracion.
final configuracionRepoProvider = Provider<ConfiguracionRepository?>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  final cache = ref.watch(cacheServiceProvider).valueOrNull;
  return ConfiguracionRepository(db, cache: cache);
});

/// Proveedores activos para dropdowns.
final proveedoresConfigProvider = FutureProvider<List<Proveedor>>((ref) {
  return ref.watch(configuracionRepoProvider)!.getProveedores();
});

/// Catálogo completo de categorías (activas e inactivas) para gestión y
/// dropdowns.
///
/// Ojo: el borrado de categorías es lógico (`activo = false`), así que si aquí
/// se filtraran las inactivas, una categoría desactivada desaparecería de
/// Configuración y no habría forma de verla ni de reactivarla (el diálogo de
/// edición tiene el switch "Activa"). Las pantallas que lo necesiten marcan
/// las inactivas con la etiqueta "(inactiva)".
final categoriasConfigProvider = FutureProvider<List<Categoria>>((ref) {
  return ref.watch(configuracionRepoProvider)!.getCategorias(soloActivos: false);
});

/// Almacenes disponibles (catálogo completo, para administración).
final almacenesAdminProvider = FutureProvider<List<Almacen>>((ref) {
  return ref.watch(configuracionRepoProvider)!.getAlmacenes(soloActivos: false);
});

/// Almacenes disponibles como lista simple de nombres (dropdowns).
final almacenesConfigProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(configuracionRepoProvider)!.getAlmacenesNombres();
});

/// Productos para la pestaña de configuración.
final productosConfigProvider = FutureProvider<List<Producto>>((ref) {
  return ref.watch(configuracionRepoProvider)!.getProductos();
});

/// Configuración POS: permitir stock negativo.
final permitirStockNegativoProvider = FutureProvider<bool>((ref) {
  return ref.watch(configuracionRepoProvider)!.getPermitirStockNegativo();
});

/// Configuración POS: almacén por defecto de producción.
final almacenProduccionDefaultProvider = FutureProvider<String>((ref) {
  return ref.watch(configuracionRepoProvider)!.getAlmacenProduccionDefault();
});

/// Periodos archivados.
final periodosConfigProvider = FutureProvider<List<Periodo>>((ref) {
  return ref.watch(configuracionRepoProvider)!.getPeriodos();
});

/// Usuario del dispositivo.
final usuarioDispositivoProvider = FutureProvider<Map<String, dynamic>?>((ref) {
  return ref.watch(configuracionRepoProvider)!.getUsuarioDispositivo();
});
