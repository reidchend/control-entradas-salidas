import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/pos_models.dart';
import '../data/pos_comanda_models.dart';
import '../data/pos_comanda_transfer_repository.dart';
import '../data/pos_providers.dart';
import 'dialogs/fusionar_comanda_dialog.dart';
import 'dialogs/mover_comanda_dialog.dart';
import 'dialogs/separar_items_dialog.dart';

/// Flujos de casilla compartidos entre el home y la pantalla de comanda:
/// mover, fusionar y separar comandas. Concentran diálogos + llamada al
/// repositorio + refresco de providers para no duplicar lógica en las vistas.

Future<void> moverComandaFlow(
  BuildContext context,
  WidgetRef ref, {
  required int comandaId,
  required String etiqueta,
  int? mesaActual,
  int? habitacionActual,
  void Function(int? mesaId, int? habitacionId)? onMovida,
}) async {
  final repo = ref.read(posComandaTransferRepoProvider);
  if (comandaId <= 0 || repo == null) {
    _snack(context, 'Comanda no guardada todavía.');
    return;
  }
  final (mesas, habs) = await _casillasLibres(ref,
      excluirMesa: mesaActual, excluirHabitacion: habitacionActual);
  if (!context.mounted) return;
  final destino = await showMoverComandaDialog(
    context,
    mesas: mesas,
    habitaciones: habs,
    subtitulo: 'Mover "$etiqueta" a:',
  );
  if (destino == null || !context.mounted) return;
  try {
    final res = await repo.moverComanda(
      comandaId,
      mesaId: destino.mesaId,
      habitacionId: destino.habitacionId,
    );
    if (!context.mounted) return;
    if (res == ResultadoTransferencia.ok) {
      _invalidarCasillas(ref);
      _snack(context, 'Comanda movida a ${destino.etiqueta}', ok: true);
      onMovida?.call(destino.mesaId, destino.habitacionId);
    } else {
      _snack(context, _mensaje(res));
    }
  } catch (e) {
    if (context.mounted) _snack(context, 'Error al mover: $e');
  }
}

Future<void> fusionarComandaFlow(
  BuildContext context,
  WidgetRef ref, {
  required int comandaId,
  required String etiqueta,
}) async {
  if (comandaId <= 0) {
    _snack(context, 'Comanda no guardada todavía.');
    return;
  }
  final repo = ref.read(posComandaTransferRepoProvider);
  if (repo == null) return;
  final activas = await ref.read(comandasActivasProvider.future);
  final otras = activas.where((c) => c.comandaId != comandaId).toList();
  if (!context.mounted) return;
  final elegida = await showFusionarComandaDialog(
    context,
    otras: otras,
    etiquetaActual: etiqueta,
  );
  if (elegida == null || !context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirmar fusión'),
      content: Text(
          'Se pasarán los productos de "${elegida.etiqueta}" a "$etiqueta".\n'
          'La casilla "${elegida.etiqueta}" quedará libre.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fusionar')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    final res = await repo.fusionarComandas(
      destinoId: comandaId,
      origenId: elegida.comandaId,
    );
    if (!context.mounted) return;
    if (res == ResultadoTransferencia.ok) {
      _invalidarCasillas(ref);
      _snack(context, 'Comanda "${elegida.etiqueta}" fusionada en "$etiqueta"',
          ok: true);
    } else {
      _snack(context, _mensaje(res));
    }
  } catch (e) {
    if (context.mounted) _snack(context, 'Error al fusionar: $e');
  }
}

/// Separa ítems de la comanda a otra casilla. Devuelve la lista de ítems que
/// quedan en la comanda original (o `null` si se cancela/falla).
Future<List<ComandaItem>?> separarComandaFlow(
  BuildContext context,
  WidgetRef ref, {
  required int comandaId,
  required List<ComandaItem> items,
  required int sesionId,
  int? mesaActual,
  int? habitacionActual,
}) async {
  if (comandaId <= 0) {
    _snack(context, 'Comanda no guardada todavía.');
    return null;
  }
  if (items.length < 2) {
    _snack(context, 'Se necesitan al menos 2 productos para separar.');
    return null;
  }
  final repo = ref.read(posComandaTransferRepoProvider);
  if (repo == null) return null;

  final sel = await showSepararItemsDialog(context, items: items);
  if (sel == null || sel.isEmpty || !context.mounted) return null;

  final selMap = {for (final s in sel) s.index: s.cantidad};
  final movidos = <ComandaItem>[];
  final restantes = <ComandaItem>[];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final cant = selMap[i];
    if (cant == null) {
      restantes.add(it);
    } else if (cant >= it.cantidad) {
      movidos.add(it);
    } else {
      movidos.add(it.copyWith(cantidad: cant));
      restantes.add(it.copyWith(cantidad: it.cantidad - cant));
    }
  }
  if (movidos.isEmpty) return null;

  final (mesas, habs) = await _casillasLibres(ref,
      excluirMesa: mesaActual, excluirHabitacion: habitacionActual);
  if (!context.mounted) return null;
  final destino = await showMoverComandaDialog(
    context,
    mesas: mesas,
    habitaciones: habs,
    titulo: 'Mover productos a',
    subtitulo:
        '${movidos.length} producto${movidos.length == 1 ? '' : 's'} a otra casilla:',
  );
  if (destino == null || !context.mounted) return null;

  try {
    final res = await repo.separarComanda(
      origenId: comandaId,
      movidos: movidos,
      restantes: restantes,
      sesionId: sesionId,
      mesaId: destino.mesaId,
      habitacionId: destino.habitacionId,
    );
    if (!context.mounted) return null;
    if (res == ResultadoTransferencia.ok) {
      _invalidarCasillas(ref);
      _snack(
          context,
          'Productos movidos a ${destino.etiqueta}'
          '${restantes.isEmpty ? ' (comanda cerrada)' : ''}',
          ok: true);
      return restantes;
    }
    _snack(context, _mensaje(res));
    return null;
  } catch (e) {
    if (context.mounted) _snack(context, 'Error al separar: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------

Future<(List<PosMesa>, List<Habitacion>)> _casillasLibres(
  WidgetRef ref, {
  int? excluirMesa,
  int? excluirHabitacion,
}) async {
  final mesas = await ref.read(mesasProvider.future);
  final habitaciones = await ref.read(habitacionesProvider.future);
  final ocupadasM = await ref.read(mesasOcupadasProvider.future);
  final ocupadasH = await ref.read(habitacionesOcupadasProvider.future);
  return (
    mesas
        .where((m) => !ocupadasM.contains(m.id) && m.id != excluirMesa)
        .toList(),
    habitaciones
        .where((h) => !ocupadasH.contains(h.id) && h.id != excluirHabitacion)
        .toList(),
  );
}

void _invalidarCasillas(WidgetRef ref) {
  ref.invalidate(mesasOcupadasProvider);
  ref.invalidate(habitacionesOcupadasProvider);
  ref.invalidate(comandasActivasProvider);
}

String _mensaje(ResultadoTransferencia res) => switch (res) {
      ResultadoTransferencia.destinoOcupado =>
        'La casilla destino ya tiene una comanda abierta.',
      ResultadoTransferencia.destinoInvalido => 'Casilla destino inválida.',
      ResultadoTransferencia.comandaNoExiste => 'La comanda ya no existe.',
      ResultadoTransferencia.sinItems => 'No hay productos para mover.',
      ResultadoTransferencia.ok => 'Listo',
    };

void _snack(BuildContext context, String texto, {bool ok = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(texto),
      backgroundColor: ok ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
    ),
  );
}
