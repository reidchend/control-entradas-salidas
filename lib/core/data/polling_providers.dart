import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/configuracion/data/configuracion_providers.dart';
import '../../features/historial/data/historial_providers.dart';
import '../../features/pos/data/pos_providers.dart';
import '../../features/pos/data/pos_session.dart';
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
    this.onTick,
  });

  final String table;
  final Duration interval;
  final void Function(WidgetRef ref) invalidate;
  final List<String> timestampCols;

  /// Se ejecuta en **cada** tick, haya cambiado la firma o no. Sirve para
  /// tareas que deben revalidarse siempre (p. ej. comprobar si el turno sigue
  /// abierto y mandar el heartbeat del participante).
  final void Function(WidgetRef ref)? onTick;
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
      invalidate: (r) {
        r.invalidate(turnoAbiertoProvider);
        r.invalidate(usuariosEnTurnoProvider);
      },
      // Revalida en cada tick (no solo cuando cambia la firma): si OTRO
      // dispositivo cierra el turno, esta terminal vuelve al login en vez de
      // seguir operando con un turno cerrado (ventas huérfanas que no entran
      // en ningún cierre). También manda el heartbeat del participante
      // (máx. 1/minuto).
      onTick: (r) =>
          unawaited(r.read(posSessionProvider.notifier).revalidarSesion()),
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
  // Firma por tabla: cantidad de filas + marca de tiempo más reciente. Se
  // compara contra la firma anterior y, si cambió (alta, baja o modificación),
  // se invalidan los providers para que la UI se refresque.
  //
  // Antes se hacía `col >= ahora` usando la hora LOCAL del cliente como
  // checkpoint inicial. Ese checkpoint nacía en el mismo instante del primer
  // tick, así que la ventana de detección era de ancho cero y el polling
  // prácticamente nunca disparaba; además mezclaba zonas horarias (las
  // columnas TEXT de comandas/ventas guardan hora local, y el chequeo usaba
  // UTC). Con la firma calculada por PostgreSQL no intervienen relojes ni
  // zonas horarias.
  final firmaAnterior = <String, String>{};
  // Errores ya avisados por tabla: evita repetir el mismo log cada tick.
  final fallosAvisados = <String>{};

  for (final b in bindings) {
    // `GREATEST` ignora NULLs, así que sirve aunque `updated_at` esté vacío
    // (p. ej. una comanda recién insertada: solo tiene `created_at`).
    //
    // IMPORTANTE: la firma combina `COUNT(*)` (agregado) con la marca más
    // reciente. La marca DEBE ir dentro de otro agregado (`MAX`): PostgreSQL
    // rechaza `SELECT COUNT(*), GREATEST(col1, col2) FROM t` con
    // "column must appear in the GROUP BY clause". Antes faltaba el `MAX`, la
    // consulta fallaba y el `catch` la silenciaba, así que el polling NUNCA
    // disparaba (ni ocupación de mesas ni cierre de turno en otros equipos).
    final marca = b.timestampCols.length == 1
        ? b.timestampCols.first
        : 'GREATEST(${b.timestampCols.join(', ')})';
    final sql = 'SELECT COUNT(*)::text || \':\' || '
        'COALESCE(MAX($marca)::text, \'\') AS firma FROM ${b.table}';
    // Evita que dos consultas del mismo timer se solapen si la red/DB tarda
    // más que el intervalo.
    var consultando = false;

    final timer = Timer.periodic(b.interval, (_) async {
      if (consultando) return;
      consultando = true;
      try {
        // La pantalla puede haberse desmontado (p. ej. el turno se cerró y el
        // router volvió al login): no usar `ref` después de dispose.
        if (!ref.context.mounted) return;
        // Tareas que deben correr siempre (p. ej. revalidar el turno), aunque
        // la firma no haya cambiado.
        b.onTick?.call(ref);

        final rows = await db.executeSql(sql);
        if (rows.isEmpty) return;
        final firma = rows.first['firma']?.toString() ?? '';
        final previa = firmaAnterior[b.table];
        firmaAnterior[b.table] = firma;
        // En el primer tick también se refresca: puede haber cambios hechos
        // entre que se abrió la app y arrancó el polling.
        if ((previa == null || previa != firma) && ref.context.mounted) {
          b.invalidate(ref);
        }
      } catch (e) {
        // Silenciar errores de polling (tabla sin las columnas, etc.), pero
        // avisar una vez por tabla para que un SQL roto no pase inadvertido.
        if (fallosAvisados.add(b.table)) {
          debugPrint('[polling] ${b.table}: $e');
        }
      } finally {
        consultando = false;
      }
    });
    timers.add(timer);
  }

  return [for (final t in timers) () => t.cancel()];
}