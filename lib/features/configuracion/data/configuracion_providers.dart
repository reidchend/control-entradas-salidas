import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/supabase_providers.dart';
import '../../../core/models/almacen.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/proveedor.dart';
import '../../../core/models/periodo.dart';
import 'configuracion_repository.dart';

/// Provider compartido del repositorio de configuracion.
final configuracionRepoProvider = Provider<ConfiguracionRepository?>((ref) {
  final db = ref.watch(supabaseServiceProvider);
  if (db == null) return null;
  final cache = ref.watch(cacheServiceProvider).valueOrNull;
  return ConfiguracionRepository(db, cache: cache);
});

/// Proveedores activos para dropdowns.
final proveedoresConfigProvider = FutureProvider<List<Proveedor>>((ref) {
  return ref.watch(configuracionRepoProvider)!.getProveedores();
});

/// Categorías activas para dropdowns.
final categoriasConfigProvider = FutureProvider<List<Categoria>>((ref) {
  return ref.watch(configuracionRepoProvider)!.getCategorias();
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
