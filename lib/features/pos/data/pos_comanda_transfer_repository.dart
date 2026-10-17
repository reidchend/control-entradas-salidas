import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/data/postgres_service.dart';
import 'pos_comanda_models.dart';

/// Resultado de una operación de casilla sobre comandas.
enum ResultadoTransferencia {
  ok,
  destinoOcupado,
  destinoInvalido,
  comandaNoExiste,
  sinItems,
}

/// Operaciones de casilla sobre comandas: **mover** una comanda a otra
/// mesa/habitación, **fusionar** dos comandas y **separar** ítems hacia otra
/// casilla. Todas van en transacción con `FOR UPDATE` sobre la casilla destino
/// para no romper la invariante "una comanda abierta por casilla".
class PosComandaTransferRepository {
  PosComandaTransferRepository(this._db);

  final PostgresService _db;

  static const Uuid _uuid = Uuid();

  /// Mueve la comanda a otra casilla (mesa o habitación). Falla si el destino
  /// ya tiene una comanda abierta.
  Future<ResultadoTransferencia> moverComanda(
    int comandaId, {
    int? mesaId,
    int? habitacionId,
  }) async {
    if (comandaId <= 0) return ResultadoTransferencia.comandaNoExiste;
    if (!_destinoValido(mesaId, habitacionId)) {
      return ResultadoTransferencia.destinoInvalido;
    }
    return _db.transaction<ResultadoTransferencia>((tx) async {
      await _bloquearDestino(tx, mesaId, habitacionId);
      final existente = await _comandaAbiertaEn(tx, mesaId, habitacionId);
      if (existente != null && existente != comandaId) {
        return ResultadoTransferencia.destinoOcupado;
      }
      final rows = await tx.client
          .from('pos_comandas')
          .select('id')
          .eq('id', comandaId)
          .limit(1);
      if (rows.isEmpty) return ResultadoTransferencia.comandaNoExiste;
      await tx.updateById('pos_comandas', comandaId, {
        'mesa_id': mesaId,
        'habitacion_id': habitacionId,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return ResultadoTransferencia.ok;
    });
  }

  /// Fusiona la comanda [origenId] dentro de [destinoId]: los ítems pasan al
  /// destino y el origen se elimina (su casilla queda libre).
  Future<ResultadoTransferencia> fusionarComandas({
    required int destinoId,
    required int origenId,
  }) async {
    if (destinoId <= 0 || origenId <= 0 || destinoId == origenId) {
      return ResultadoTransferencia.destinoInvalido;
    }
    return _db.transaction<ResultadoTransferencia>((tx) async {
      // Bloquear en orden de id para evitar interbloqueos.
      final orden = [destinoId, origenId]..sort();
      for (final id in orden) {
        await tx.executeSql(
          'SELECT id FROM pos_comandas WHERE id = \$1 FOR UPDATE',
          params: [id],
        );
      }
      final destino = await _leerComanda(tx, destinoId);
      final origen = await _leerComanda(tx, origenId);
      if (destino == null || origen == null) {
        return ResultadoTransferencia.comandaNoExiste;
      }

      final destinoItems =
          ComandaItem.listFromJson(destino['items_json'] as String?);
      final origenItems =
          ComandaItem.listFromJson(origen['items_json'] as String?);
      final fusionados = _fusionarItems(destinoItems, origenItems);
      final total = fusionados.fold<double>(0, (s, i) => s + i.subtotal);
      final ahora = DateTime.now().toIso8601String();

      await tx.updateById('pos_comandas', destinoId, {
        'items_json': jsonEncode([for (final i in fusionados) i.toJson()]),
        'total': total,
        'updated_at': ahora,
      });
      await tx.deleteById('pos_comandas', origenId);
      return ResultadoTransferencia.ok;
    });
  }

  /// Separa [movidos] de la comanda [origenId] hacia una casilla nueva
  /// ([mesaId]/[habitacionId]); deja [restantes] en el origen (o lo borra si
  /// no queda nada).
  Future<ResultadoTransferencia> separarComanda({
    required int origenId,
    required List<ComandaItem> movidos,
    required List<ComandaItem> restantes,
    required int sesionId,
    int? mesaId,
    int? habitacionId,
  }) async {
    if (movidos.isEmpty) return ResultadoTransferencia.sinItems;
    if (origenId <= 0 || sesionId == 0) {
      return ResultadoTransferencia.comandaNoExiste;
    }
    if (!_destinoValido(mesaId, habitacionId)) {
      return ResultadoTransferencia.destinoInvalido;
    }
    return _db.transaction<ResultadoTransferencia>((tx) async {
      await _bloquearDestino(tx, mesaId, habitacionId);
      final ocupada = await _comandaAbiertaEn(tx, mesaId, habitacionId);
      if (ocupada != null) return ResultadoTransferencia.destinoOcupado;

      await tx.executeSql(
        'SELECT id FROM pos_comandas WHERE id = \$1 FOR UPDATE',
        params: [origenId],
      );
      final origen = await _leerComanda(tx, origenId);
      if (origen == null) return ResultadoTransferencia.comandaNoExiste;

      final ahora = DateTime.now().toIso8601String();
      final totalMovidos = movidos.fold<double>(0, (s, i) => s + i.subtotal);
      await tx.insert('pos_comandas', {
        'sesion_id': sesionId,
        'mesa_id': mesaId,
        'habitacion_id': habitacionId,
        'estado': 'abierta',
        'total': totalMovidos,
        'items_json': jsonEncode([for (final i in movidos) i.toJson()]),
        'sync_uuid': _uuid.v4(),
        'created_at': ahora,
        'updated_at': ahora,
      });

      if (restantes.isEmpty) {
        await tx.deleteById('pos_comandas', origenId);
      } else {
        final totalRestantes =
            restantes.fold<double>(0, (s, i) => s + i.subtotal);
        await tx.updateById('pos_comandas', origenId, {
          'items_json': jsonEncode([for (final i in restantes) i.toJson()]),
          'total': totalRestantes,
          'updated_at': ahora,
        });
      }
      return ResultadoTransferencia.ok;
    });
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  static bool _destinoValido(int? mesaId, int? habitacionId) =>
      (mesaId != null) != (habitacionId != null);

  Future<void> _bloquearDestino(
      PostgresService tx, int? mesaId, int? habitacionId) async {
    if (mesaId != null) {
      await tx.executeSql(
        'SELECT id FROM pos_mesas WHERE id = \$1 FOR UPDATE',
        params: [mesaId],
      );
    } else if (habitacionId != null) {
      await tx.executeSql(
        'SELECT id FROM habitaciones WHERE id = \$1 FOR UPDATE',
        params: [habitacionId],
      );
    }
  }

  static Future<int?> _comandaAbiertaEn(
    PostgresService tx,
    int? mesaId,
    int? habitacionId,
  ) async {
    if (mesaId != null) {
      final rows = await tx.client
          .from('pos_comandas')
          .select('id')
          .eq('mesa_id', mesaId)
          .eq('estado', 'abierta')
          .order('id', ascending: false)
          .limit(1);
      return rows.isEmpty ? null : rows.first['id'] as int;
    }
    if (habitacionId != null) {
      final rows = await tx.client
          .from('pos_comandas')
          .select('id')
          .eq('habitacion_id', habitacionId)
          .eq('estado', 'abierta')
          .order('id', ascending: false)
          .limit(1);
      return rows.isEmpty ? null : rows.first['id'] as int;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _leerComanda(
      PostgresService tx, int id) async {
    final rows =
        await tx.client.from('pos_comandas').select().eq('id', id).limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Fusiona dos listas renglón a renglón (mismo id/tipo/cliente/contornos se
  /// suma). Si el origen usa sub-cuentas, se renumera para no chocar con las
  /// del destino.
  static List<ComandaItem> _fusionarItems(
    List<ComandaItem> destino,
    List<ComandaItem> origen,
  ) {
    final destinoUsaCuentas = destino.any((i) => i.cuenta != 1);
    final origenUsaCuentas = origen.any((i) => i.cuenta != 1);
    final maxCuenta =
        destino.fold<int>(1, (m, i) => i.cuenta > m ? i.cuenta : m);
    final base = (origenUsaCuentas && destinoUsaCuentas) ? maxCuenta : 0;

    final acumulado = <String, ComandaItem>{};
    final orden = <String>[];

    void add(ComandaItem it) {
      final key = _clave(it);
      final prev = acumulado[key];
      if (prev == null) {
        acumulado[key] = it;
        orden.add(key);
      } else {
        prev.cantidad += it.cantidad;
      }
    }

    for (final it in destino) {
      add(it.copyWith());
    }
    for (final it in origen) {
      final cuenta = origenUsaCuentas ? it.cuenta + base : 1;
      add(it.copyWith(cuenta: cuenta));
    }
    return [for (final k in orden) acumulado[k]!];
  }

  static String _clave(ComandaItem it) {
    final contornos = it.contornos
        .map((c) => '${c.id ?? ''}:${c.nombre}:${c.cantidad}')
        .join(';');
    return '${it.id}|${it.tipo}|${it.cuenta}|${it.precio}|$contornos';
  }
}
