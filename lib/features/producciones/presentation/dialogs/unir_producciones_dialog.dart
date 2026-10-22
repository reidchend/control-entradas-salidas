import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/receta.dart';
import '../../data/producciones_providers.dart';
import '../../data/producciones_repository.dart';

/// Diálogo para elegir con qué producción pendiente de la misma receta unir
/// la producción actual. `produccionActual` se queda (destino); la seleccionada
/// se absorbe en ella (origen). Devuelve el `id` de la producción origen, o
/// `null` si se canceló o no hay opciones.
Future<int?> showUnirProduccionesDialog({
  required BuildContext context,
  required WidgetRef ref,
  required ProduccionInfo produccionActual,
  required Receta receta,
}) async {
  final repo = ref.read(produccionesRepoProvider)!;
  final pendientes = await repo.getProduccionesPorEstado('pendiente');
  if (!context.mounted) return null;

  final opciones = pendientes
      .where(
          (p) => p.id != produccionActual.id && p.recetaId == produccionActual.recetaId)
      .toList()
    ..sort((a, b) {
      final fa = a.fechaProduccion ?? DateTime(1970);
      final fb = b.fechaProduccion ?? DateTime(1970);
      return fb.compareTo(fa);
    });

  if (opciones.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No hay producciones para unir'),
        content: const Text(
            'No hay otras producciones pendientes de esta receta para unir.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Aceptar')),
        ],
      ),
    );
    return null;
  }

  int? seleccionada;
  return showDialog<int?>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx2, setSt) {
          return AlertDialog(
            title: const Text('Unir producciones'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'La producción #${produccionActual.id} se quedará y '
                    'absorberá la que selecciones. Sus cantidades se sumarán.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Solo se unen producciones pendientes de la misma receta.',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(ctx2).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  for (final o in opciones)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Radio<int>(
                        value: o.id,
                        groupValue: seleccionada,
                        onChanged: (v) => setSt(() => seleccionada = v),
                      ),
                      title: Text(
                          'Producción #${o.id} · x${_fmtCant(o.cantidad)}'),
                      subtitle: Text(
                        '${_fmtFecha(o.fechaProduccion)} · ${o.usuario ?? 'Sistema'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx2, null),
                  child: const Text('Cancelar')),
              FilledButton(
                onPressed: seleccionada == null ? null : () => Navigator.pop(ctx2, seleccionada),
                child: const Text('Unir'),
              ),
            ],
          );
        },
      );
    },
  );
}

String _fmtCant(double c) {
  if (c == c.roundToDouble()) return c.toInt().toString();
  return c.toStringAsFixed(3);
}

String _fmtFecha(DateTime? d) {
  if (d == null) return '';
  String p(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}
