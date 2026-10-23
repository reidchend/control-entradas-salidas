import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:control_entradas_salidas/core/auth/session_controller.dart';

import '../../../../core/models/existencia.dart';
import '../../../../core/models/producto.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../data/stock_repository.dart';
import 'ajuste_dialog.dart';

/// Diálogo de existencias de un producto (porta `build_existencias_dialog`).
/// Lista las existencias por almacén y permite ajustar cada una.
Future<void> showExistenciasDialog(
  BuildContext context,
  WidgetRef ref,
  Producto producto,
  StockRepository repo,
) async {
  var existencias = await repo.getExistenciasProducto(producto.id);
  if (!context.mounted) return;

  // Un producto sin existencias registradas también debe poder ajustarse:
  // es justo el caso de la primera toma de inventario, donde el producto está
  // en 0 porque nunca tuvo movimientos y hay que asignarle el conteo físico
  // real. Antes el diálogo se cerraba con un snackbar y no había forma.
  // Se listan los almacenes conocidos con stock 0; `ajustarExistencia` ya
  // crea la fila de existencia al confirmar.
  if (existencias.isEmpty) {
    final almacenes = await repo.getAlmacenes();
    if (!context.mounted) return;
    final nombres = <String>{...almacenes};
    final predeterminado = producto.almacenPredeterminado;
    if (predeterminado.isNotEmpty) nombres.add(predeterminado);
    existencias = [
      for (final a in nombres)
        Existencia(
          id: 0,
          productoId: producto.id,
          almacen: a,
          cantidad: 0,
          unidad: producto.unidadMedida,
        ),
    ];
  }

  final esPesable = producto.esPesable;

  String fmtCant(double cant) => esPesable
      ? '${cant.toStringAsFixed(3)} ${producto.unidadMedida}'
      : '${cant.round()} ${producto.unidadMedida}';

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setSt) {
        return AlertDialog(
          title: Text('Existencias: ${producto.nombre}'),
          content: SizedBox(
            width: modalContentWidth(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unidad: ${producto.unidadMedida}   •   Stock mínimo: ${producto.stockMinimo.round()}',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final e in existencias)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Theme.of(context).colorScheme.outlineVariant),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.almacen.capitalize(),
                                        style: const TextStyle(
                                            fontSize: 15, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'Stock actual: ${fmtCant(e.cantidad)}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.edit, size: 18),
                                  label: const Text('Ajustar'),
                                  onPressed: () async {
                                    final resultado = await showAjusteDialog(
                                      dialogCtx,
                                      producto: producto,
                                      almacen: e.almacen,
                                      cantidadActual: e.cantidad,
                                    );
                                    if (resultado != null && dialogCtx.mounted) {
                                      final session = ref.read(sessionProvider);
                                      final usuario = session is Authenticated
                                          ? session.nombre
                                          : 'Sistema';
                                      await repo.ajustarExistencia(
                                        productoId: producto.id,
                                        almacen: e.almacen,
                                        nuevaCantidad: resultado.$1,
                                        motivo: resultado.$2,
                                        usuario: usuario,
                                      );
                                      if (!dialogCtx.mounted) return;
                                      // Reabrir con valores actualizados.
                                      Navigator.pop(dialogCtx);
                                      await showExistenciasDialog(
                                          context, ref, producto, repo);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    ),
  );
}

extension _StringCapitalize on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

