import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/receta.dart';
import '../../../producciones/data/producciones_providers.dart';
import '../../../producciones/data/producciones_repository.dart';

/// Diálogo para elegir a qué lote pendiente vincular una nueva entrada de
/// producción, o crear uno nuevo.
///
/// Devuelve el `id` de la producción destino (lote existente), o `null` si
/// se debe crear un lote nuevo, o `null` también si se cancela.
///
/// Se usa desde el panel de Inventario **antes** de abrir el modal de
/// carga, para evitar crear lotes duplicados sin querer.
Future<int?> showSeleccionarLoteProduccionDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Receta receta,
}) async {
  final repo = ref.read(produccionesRepoProvider)!;
  final pendientes = await repo.getProduccionesPorEstado('pendiente');
  if (!context.mounted) return null;

  final opciones = pendientes
      .where((p) => p.recetaId == receta.id)
      .toList()
    ..sort((a, b) {
      final fa = a.fechaProduccion ?? DateTime(1970);
      final fb = b.fechaProduccion ?? DateTime(1970);
      return fb.compareTo(fa);
    });

  int? seleccionada;

  return showDialog<int?>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx2, setSt) {
          return AlertDialog(
            title: const Text('Vincular a lote existente'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ya existen lotes pendientes de "${receta.nombre}". '
                    'Seleccioná a cuál sumar esta entrada, o creá uno nuevo.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (opciones.isNotEmpty) ...[
                    const Text(
                      'Lotes pendientes:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    for (final l in opciones)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Radio<int>(
                          value: l.id,
                          groupValue: seleccionada,
                          onChanged: (v) => setSt(() => seleccionada = v),
                        ),
                        title: Text('Lote #${l.id}'),
                        subtitle: Text(
                          'x${_fmtCant(l.cantidad)} · '
                          '${_fmtFecha(l.fechaProduccion)} · '
                          '${l.usuario ?? 'Sistema'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    const Divider(height: 16),
                  ],
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('Crear lote nuevo'),
                    onTap: () => setSt(() => seleccionada = null),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2, null),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx2, seleccionada),
                child: const Text('Continuar'),
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
