import 'package:flutter/material.dart';

import '../../data/activo_tipo.dart';

/// Pregunta qué hacer cuando la IA propone un activo que ya existe en el
/// catálogo con el mismo nombre.
///
/// Devuelve `true` para sumar una unidad al tipo existente, `false` para crear
/// un tipo nuevo con los datos propuestos, o `null` si se cancela.
Future<bool?> showTipoCoincidenteDialog(
  BuildContext context, {
  required ActivoTipo existente,
  required int unidades,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final detalle = [
        if ((existente.grupo ?? '').trim().isNotEmpty) existente.grupo!.trim(),
        if ((existente.modelo ?? '').trim().isNotEmpty)
          existente.modelo!.trim(),
      ].join(' · ');

      return AlertDialog(
        title: const Text('Ya está en el catálogo'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La foto coincide con un activo que ya tenés registrado. '
                'Podés sumar una unidad nueva (por ejemplo, en otra '
                'ubicación) o crear un tipo aparte.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existente.nombre,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (detalle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detalle,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      unidades == 0
                          ? 'Sin unidades registradas'
                          : unidades == 1
                              ? '1 unidad registrada'
                              : '$unidades unidades registradas',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w600,
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
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Crear tipo nuevo'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Agregar al existente'),
          ),
        ],
      );
    },
  );
}
