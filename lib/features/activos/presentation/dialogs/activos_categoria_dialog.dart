import 'package:flutter/material.dart';

import '../../data/activos_categoria.dart';

/// Muestra el diálogo crear/editar categoría y devuelve la categoría capturada,
/// o `null` si se canceló.
Future<ActivosCategoria?> showActivosCategoriaDialog(
  BuildContext context, {
  ActivosCategoria? categoria,
}) async {
  final nombreCtrl = TextEditingController(text: categoria?.nombre ?? '');
  var color = categoria?.color ?? '#2196F3';
  const colores = [
    '#2196F3', '#4CAF50', '#FF9800', '#F44336', '#9C27B0',
    '#00BCD4', '#795548', '#E91E63', '#3F51B5', '#607D8B',
  ];

  return showDialog<ActivosCategoria>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(categoria == null ? 'Nueva Categoría' : 'Editar Categoría'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nombreCtrl,
            decoration: const InputDecoration(labelText: 'Nombre *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final c in colores)
                GestureDetector(
                  onTap: () => color = c,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(int.parse(c.replaceFirst('#', '0xFF'))),
                    child: color == c ? const Icon(Icons.check, size: 16) : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final nombre = nombreCtrl.text.trim();
            if (nombre.isEmpty) return;
            Navigator.pop(
              context,
              ActivosCategoria(
                id: categoria?.id ?? 0,
                nombre: nombre,
                color: color,
                activo: categoria?.activo ?? true,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}