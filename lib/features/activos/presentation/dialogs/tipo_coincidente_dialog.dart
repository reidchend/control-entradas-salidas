import 'package:flutter/material.dart';

import '../../data/activo_tipo.dart';

/// Qué hacer con un tipo existente cuando la IA propone un activo que ya
/// existe en el catálogo.
enum AccionTipoExistente {
  /// Usar el tipo existente tal como está (nombre, grupo, modelo sin cambios).
  usarExistente,

  /// Actualizar el tipo existente con los datos de la IA (nombre, grupo,
  /// modelo, categoría). Todas las unidades de ese tipo heredan los cambios.
  sobrescribirExistente,

  /// Crear un tipo nuevo con los datos de la IA.
  crearNuevo,
}

/// Pregunta qué hacer cuando la IA propone un activo que ya existe en el
/// catálogo con el mismo nombre (o nombre similar).
///
/// Devuelve [AccionTipoExistente.usarExistente] para sumar una unidad al tipo
/// existente sin cambios, [AccionTipoExistente.sobrescribirExistente] para
/// actualizar el tipo existente con los datos de la IA, o
/// [AccionTipoExistente.crearNuevo] para crear un tipo aparte, o `null` si se
/// cancela.
Future<AccionTipoExistente?> showTipoCoincidenteDialog(
  BuildContext context, {
  required ActivoTipo existente,
  required int unidades,
}) {
  return showDialog<AccionTipoExistente>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final detalle = [
        if ((existente.grupo ?? '').trim().isNotEmpty)
          existente.grupo!.trim(),
        if ((existente.modelo ?? '').trim().isNotEmpty)
          existente.modelo!.trim(),
      ].join(' · ');

      return AlertDialog(
        title: const Text('Ya está en el catálogo'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La foto coincide con un activo que ya tenés registrado. '
                'Elegí qué hacer:',
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
              const SizedBox(height: 12),
              const Text(
                '¿Qué hacés con el tipo existente?',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link, color: Colors.blue),
                title: const Text(
                  'Usar tipo existente',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  'Se suma una unidad al tipo tal cual está.',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                onTap: () =>
                    Navigator.pop(ctx, AccionTipoExistente.usarExistente),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit, color: Colors.orange),
                title: const Text(
                  'Sobrescribir con datos de la foto',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  'Actualiza nombre, grupo y modelo del tipo; todas sus unidades heredan los cambios.',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                onTap: () => Navigator.pop(
                  ctx,
                  AccionTipoExistente.sobrescribirExistente,
                ),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add, color: Colors.green),
                title: const Text(
                  'Crear tipo nuevo',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  'El tipo existente no cambia.',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                onTap: () => Navigator.pop(ctx, AccionTipoExistente.crearNuevo),
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
