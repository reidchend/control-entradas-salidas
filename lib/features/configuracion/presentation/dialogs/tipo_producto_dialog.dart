import 'package:flutter/material.dart';

import '../../../../core/models/tipo_producto.dart';

/// Crea o renombra un tipo de producto. Devuelve el nombre confirmado, o
/// `null` si se canceló. [nombresExistentes] valida duplicados comparando en
/// minúsculas (en la BD conviven escrituras variadas del mismo concepto).
Future<String?> showTipoProductoDialog(
  BuildContext context, {
  required List<String> nombresExistentes,
  TipoProducto? tipo,
}) async {
  final esNuevo = tipo == null;
  final ctrl = TextEditingController(text: tipo?.nombre ?? '');
  String? error;

  return await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setSt) {
        void confirmar() {
          final nombre = ctrl.text.trim();
          if (nombre.isEmpty) {
            setSt(() => error = 'Escribí un nombre');
            return;
          }
          final duplicado = nombresExistentes
              .any((n) => n.toLowerCase() == nombre.toLowerCase());
          if (duplicado) {
            setSt(() => error = 'Ya existe un tipo con ese nombre');
            return;
          }
          Navigator.pop(ctx2, nombre);
        }

        return AlertDialog(
          title: Text(esNuevo ? 'Nuevo tipo de producto' : 'Renombrar tipo'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!esNuevo) ...[
                  Text(
                    'Al renombrar, ${tipo!.enUso} producto(s) que usan '
                    '"${tipo.nombre}" pasan al nombre nuevo.',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(ctx2).colorScheme.onSurfaceVariant),
                  ),
                  if (tipo.esDelSistema && tipo.rol != 'ninguno')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Este tipo liga flujos del sistema por ROL: '
                        'producción, colores y filtros siguen funcionando '
                        'igual con el nombre nuevo.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx2).colorScheme.tertiary),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Nombre del tipo',
                    errorText: error,
                  ),
                  onSubmitted: (_) => confirmar(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: confirmar,
              child: Text(esNuevo ? 'Crear' : 'Guardar'),
            ),
          ],
        );
      },
    ),
  );
}
