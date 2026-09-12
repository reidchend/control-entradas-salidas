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
    this.timestampCols = const ['updated_at', 'created_at'],
  });

  final String table;
  final Duration interval;
  final void Function(WidgetRef ref) invalidate;
  final List<String> timestampCols;
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
      table: 'pos_ventas',
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
      timestampCols: const ['created_at'],
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
        // Verificar si hay cambios recientes (últimos interval*2), usando
        // solo las columnas que existen en la tabla. Cada condición usa un
        // placeholder distinto (`$1`, `$2`, ...) porque el proxy web (psycopg)
        // no permite reutilizar `$1` en dos lugares del mismo query.
        final cutoff = DateTime.now().subtract(b.interval * 2).toIso8601String();
        final cond = [
          for (var i = 0; i < b.timestampCols.length; i++)
            '${b.timestampCols[i]} >= \$${i + 1}',
        ].join(' OR ');
        final result = await db.executeSql(
          'SELECT 1 FROM ${b.table} WHERE $cond LIMIT 1',
          params: [for (final _ in b.timestampCols) cutoff],
        );
        if (result.isNotEmpty) {
          b.invalidate(ref);
        }
      } catch (_) {
        // Silenciar errores de polling (tabla sin las columnas, etc.)
      }
    });
    timers.add(timer);
  }

  return [for (final t in timers) () => t.cancel()];
}