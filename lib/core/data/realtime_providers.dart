import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/configuracion/data/configuracion_providers.dart';
import '../../features/historial/data/historial_providers.dart';
import '../../features/pos/data/pos_providers.dart';
import 'realtime_service.dart';

/// Mapa de tablas -> providers Riverpod que deben invalidarse cuando
/// llega un evento Realtime.
typedef _TableInvalidator = void Function(WidgetRef ref);

class _RealtimeBindings {
  final String table;
  final Set<PostgresChangeEvent> events;
  final _TableInvalidator invalidate;

  const _RealtimeBindings({
    required this.table,
    required this.events,
    required this.invalidate,
  });
}

/// Inicializa las suscripciones Realtime para tablas del POS.
///
/// Stock y WhatsApp manejan sus propias suscripciones internamente
/// (llaman _reload/_refrescar al recibir eventos).
List<RealtimeSubscription> initRealtimeSubscriptions(
  RealtimeService service,
  WidgetRef ref,
) {
  final bindings = [
    _RealtimeBindings(
      table: 'pos_sesiones',
      events: {PostgresChangeEvent.insert, PostgresChangeEvent.update},
      invalidate: (r) {
        r.invalidate(turnosActivosProvider);
      },
    ),
    _RealtimeBindings(
      table: 'pos_comandas',
      events: {PostgresChangeEvent.insert, PostgresChangeEvent.update, PostgresChangeEvent.delete},
      invalidate: (r) {
        r.invalidate(comandasAbiertasProvider);
        r.invalidate(mesasOcupadasProvider);
        r.invalidate(comandasActivasProvider);
        r.invalidate(habitacionesOcupadasProvider);
      },
    ),
    _RealtimeBindings(
      table: 'pos_venta_detalle',
      events: {PostgresChangeEvent.insert, PostgresChangeEvent.update},
      invalidate: (r) {
        r.invalidate(ventasProvider);
        r.invalidate(ventasHoyProvider);
        r.invalidate(ultimaVentaVigenteProvider);
      },
    ),
    // --- Admin / Catalogos ---
    _RealtimeBindings(
      table: 'categorias',
      events: {PostgresChangeEvent.insert, PostgresChangeEvent.update, PostgresChangeEvent.delete},
      invalidate: (r) {
        r.invalidate(categoriasConfigProvider);
      },
    ),
    _RealtimeBindings(
      table: 'productos',
      events: {PostgresChangeEvent.insert, PostgresChangeEvent.update, PostgresChangeEvent.delete},
      invalidate: (r) {
        r.invalidate(productosConfigProvider);
      },
    ),
    _RealtimeBindings(
      table: 'proveedores',
      events: {PostgresChangeEvent.insert, PostgresChangeEvent.update, PostgresChangeEvent.delete},
      invalidate: (r) {
        r.invalidate(proveedoresConfigProvider);
      },
    ),
    _RealtimeBindings(
      table: 'facturas',
      events: {PostgresChangeEvent.insert, PostgresChangeEvent.update, PostgresChangeEvent.delete},
      invalidate: (r) {
        r.invalidate(facturasProvider);
      },
    ),
  ];

  final subs = <RealtimeSubscription>[];
  for (final b in bindings) {
    final sub = service.subscribe(
      table: b.table,
      events: b.events,
    );
    sub.stream.listen((_) => b.invalidate(ref));
    subs.add(sub);
  }
  return subs;
}
