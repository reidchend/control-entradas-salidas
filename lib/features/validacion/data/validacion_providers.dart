import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import 'temporales_repository.dart';
import 'validacion_repository.dart';

final validacionRepoProvider = Provider<ValidacionRepository?>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  return ValidacionRepository(db);
});

final temporalesRepoProvider = Provider<TemporalesRepository>((ref) {
  final db = ref.watch(postgresServiceProvider);
  return TemporalesRepository(db!);
});

/// Polling de temporales viviendo en el provider: `autoDispose` cancela el
/// timer cuando no hay listeners (pantallas/diálogos cerrados) en lugar de
/// sondear la BD cada 10s durante toda la vida de la app.
final temporalesProvider =
    StreamProvider.autoDispose<List<TemporalData>>((ref) {
  final repo = ref.watch(temporalesRepoProvider);
  final controller = StreamController<List<TemporalData>>.broadcast();
  Timer? timer;
  Future<void> refrescar() async {
    try {
      final items = await repo.getTemporales();
      if (!controller.isClosed) controller.add(items);
    } catch (_) {
      // Silenciar errores de polling
    }
  }

  timer = Timer.periodic(const Duration(seconds: 10), (_) => refrescar());
  refrescar();
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

final proveedoresProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(validacionRepoProvider)!.getProveedores();
});

/// Entradas pendientes de validar (movimientos 'entrada' sin factura_id).
/// Se invalida tras validar o eliminar para que la lista se refresque.
final entradasPendientesProvider = FutureProvider.autoDispose
    .family<List<EntradaPendiente>, String>((ref, search) async {
  final repo = ref.watch(validacionRepoProvider)!;
  return repo.getEntradasPendientes(search: search);
});