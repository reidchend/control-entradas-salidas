import 'package:flutter/material.dart';

import '../../data/activo_tipo.dart';
import '../../data/activo_identificado.dart';

/// Resultado al elegir un tipo similar.
class TipoSimilarSeleccion {
  const TipoSimilarSeleccion({
    required this.tipo,
    this.sobrescribir = false,
  });

  /// Tipo existente elegido.
  final ActivoTipo tipo;

  /// Si es true, se actualizará el tipo con los datos extraídos por la IA.
  final bool sobrescribir;
}

/// Pregunta al usuario si quiere vincular la entrada de producción a un tipo
/// de activo existente similar al identificado por la IA, o crear uno nuevo.
///
/// Devuelve un [TipoSimilarSeleccion] con el tipo elegido y si hay que
/// sobrescribirlo con los datos de la IA, o `null` si el usuario prefiere
/// crear un tipo nuevo, o `null` si cancela.
Future<TipoSimilarSeleccion?> showTipoSimilarDialog({
  required BuildContext context,
  required List<ActivoTipo> similares,
  required ActivoIdentificado identificado,
}) {
  return showDialog<TipoSimilarSeleccion>(
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
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
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
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: similares.length,
                  itemBuilder: (context, i) {
                    final t = similares[i];
                    return ListTile(
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
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () async {
                        final accion = await showDialog<String>(
                          context: ctx,
                          builder: (c2) {
                            final s2 = Theme.of(c2).colorScheme;
                            final det2 = [
                              if ((t.grupo ?? '').trim().isNotEmpty)
                                t.grupo!.trim(),
                              if ((t.modelo ?? '').trim().isNotEmpty)
                                t.modelo!.trim(),
                            ].join(' · ');
                            return AlertDialog(
                              title: const Text('¿Qué hacer con este tipo?'),
                              content: SizedBox(
                                width: 420,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: s2.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t.nombre,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: s2.onSurface,
                                            ),
                                          ),
                                          if (det2.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              det2,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: s2.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.link,
                                          color: Colors.blue),
                                      title: const Text(
                                        'Usar tipo existente',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        'Se vincula tal como está ahora.',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: s2.onSurfaceVariant),
                                      ),
                                      onTap: () => Navigator.pop(c2, 'usar'),
                                    ),
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.edit,
                                          color: Colors.orange),
                                      title: const Text(
                                        'Corregir con datos de la IA',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        'Actualizar nombre, grupo y modelo con «${identificado.nombre}». Todas las unidades de este tipo heredarán los cambios.',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: s2.onSurfaceVariant),
                                      ),
                                      onTap: () =>
                                          Navigator.pop(c2, 'sobrescribir'),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c2),
                                  child: const Text('Cancelar'),
                                ),
                              ],
                            );
                          },
                        );
                        if (accion == 'usar') {
                          Navigator.pop(ctx,
                              TipoSimilarSeleccion(tipo: t, sobrescribir: false));
                        } else if (accion == 'sobrescribir') {
                          Navigator.pop(ctx,
                              TipoSimilarSeleccion(tipo: t, sobrescribir: true));
                        }
                      },
                    );
                  },
                ),
              ),
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
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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
