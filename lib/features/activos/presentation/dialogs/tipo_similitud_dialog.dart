import 'package:flutter/material.dart';

import '../../data/activo_tipo.dart';
import '../../data/activo_identificado.dart';

/// Pregunta al usuario si quiere vincular la entrada de producción a un tipo
/// de activo existente similar al identificado por la IA, o crear uno nuevo.
///
/// Devuelve el `ActivoTipo` existente elegido, o `null` si el usuario
/// prefiere crear un tipo nuevo con los datos de la IA, o `null` si cancela.
Future<ActivoTipo?> showTipoSimilarDialog({
  required BuildContext context,
  required List<ActivoTipo> similares,
  required ActivoIdentificado identificado,
}) {
  return showDialog<ActivoTipo>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final detalle = [
        if ((identificado.marca ?? '').trim().isNotEmpty)
          'Marca: ${identificado.marca!.trim()}',
        if ((identificado.modelo ?? '').trim().isNotEmpty)
          'Modelo: ${identificado.modelo!.trim()}',
      ].join(' · ');

      return AlertDialog(
        title: const Text('¿Tipo existente o nuevo?'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La IA reconoció «${identificado.nombre}». '
                'Ya existen tipos similares en el catálogo:',
                style: TextStyle(
                    fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (detalle.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    detalle,
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Tipo existente:',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ...similares.map((t) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t.nombre,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if ((t.grupo ?? '').trim().isNotEmpty) t.grupo!.trim(),
                    if ((t.modelo ?? '').trim().isNotEmpty)
                      t.modelo!.trim(),
                  ].join(' · '),
                  style: TextStyle(fontSize: 11,
                      color: scheme.onSurfaceVariant),
                ),
                trailing: const Icon(Icons.link, size: 18),
                onTap: () => Navigator.pop(ctx, t),
              )),
              const Divider(height: 16),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add, color: Colors.green),
                title: const Text(
                  'Crear tipo nuevo',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '«${identificado.nombre}»',
                  style: TextStyle(fontSize: 11,
                      color: scheme.onSurfaceVariant),
                ),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      );
    },
  );
}
