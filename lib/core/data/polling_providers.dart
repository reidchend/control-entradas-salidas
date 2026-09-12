import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/configuracion/data/configuracion_providers.dart';
import '../../features/historial/data/historial_providers.dart';
import '../../features/pos/data/pos_providers.dart';
import 'postgres_service.dart';

/// Configuración de polling para reemplazar Realtime.
///
/// Como PostgreSQL directo no tiene Realtime, usamos polling periódico.
/// Cada tabla tiene su intervalo; las críticas (comandas, ventas) más frecuentes.
class PollingConfig {
  const PollingConfig({
    required this.table,
    required this.interval,
    required this.invalidate,
  });

  final String table;
  final Duration interval;
  final void Function(WidgetRef ref) invalidate;
}

/// Inicializa los timers de polling para tablas críticas.
///
/// Retorna lista de funciones de cancelación (cleanup).
List<void Function()> initPollingSubscriptions(
  WidgetRef ref, {
  PostgresService? db,
}) {
  if (db == null) return [];

  final bindings = [
    PollingConfig(
      table: 'pos_sesiones',
      interval: const Duration(seconds: 10),
      invalidate: (r) => r.invalidate(turnosActivosProvider),
    ),
    PollingConfig(
      table: 'pos_comandas',
      interval: const Duration(seconds: 5),
      invalidate: (r) {
        r.invalidate(comandasAbiertasProvider);
        r.invalidate(mesasOcupadasProvider);
        r.invalidate(comandasActivasProvider);
        r.invalidate(habitacionesOcupadasProvider);
      },
    ),
    PollingConfig(
      table: 'pos_venta_detalle',
      interval: const Duration(seconds: 10),
      invalidate: (r) {
        r.invalidate(ventasProvider);
        r.invalidate(ventasHoyProvider);
        r.invalidate(ultimaVentaVigenteProvider);
      },
    ),
    // --- Admin / Catalogos ---
    PollingConfig(
      table: 'categorias',
      interval: const Duration(seconds: 30),
      invalidate: (r) => r.invalidate(categoriasConfigProvider),
    ),
    PollingConfig(
      table: 'productos',
      interval: const Duration(seconds: 30),
      invalidate: (r) => r.invalidate(productosConfigProvider),
    ),
    PollingConfig(
      table: 'proveedores',
      interval: const Duration(seconds: 30),
      invalidate: (r) => r.invalidate(proveedoresConfigProvider),
    ),
    PollingConfig(
      table: 'facturas',
      interval: const Duration(seconds: 15),
      invalidate: (r) => r.invalidate(facturasProvider),
    ),
  ];

  final timers = <Timer>[];
  for (final b in bindings) {
    final timer = Timer.periodic(b.interval, (_) async {
      try {
        // Verificar si hay cambios recientes (últimos interval*2)
        final cutoff = DateTime.now().subtract(b.interval * 2).toIso8601String();
        final result = await db.executeSql(
          'SELECT 1 FROM ${b.table} WHERE updated_at >= \$1 OR created_at >= \$1 LIMIT 1',
          params: [cutoff],
        );
        if (result.isNotEmpty) {
          b.invalidate(ref);
        }
      } catch (_) {
        // Silenciar errores de polling
      }
    });
    timers.add(timer);
  }

  return [for (final t in timers) () => t.cancel()];
}