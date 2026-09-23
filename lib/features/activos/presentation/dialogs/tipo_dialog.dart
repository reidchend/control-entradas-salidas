import 'package:flutter/material.dart';

import '../../data/activo_tipo.dart';
import '../../data/activos_categoria.dart';
import '../widgets/opciones_field.dart';

/// Diálogo crear/editar un tipo del catálogo (nombre, grupo, modelo y
/// categoría). Centraliza la identidad del activo: al agregar unidades
/// nunca se vuelven a escribir estos campos.
Future<ActivoTipo?> showTipoDialog(
  BuildContext context, {
  ActivoTipo? tipo,
  List<ActivosCategoria> categorias = const [],
  List<String> grupos = const [],
  List<String> modelos = const [],
  String? grupoPreset,
  String? modeloPreset,
}) async {
  final nombreCtrl = TextEditingController(text: tipo?.nombre ?? '');
  final grupoCtrl = TextEditingController(
      text: tipo?.grupo?.trim() ?? grupoPreset ?? '');
  final modeloCtrl = TextEditingController(
      text: tipo?.modelo?.trim() ?? modeloPreset ?? '');
  var categoriaId = tipo?.categoriaId;

  return showDialog<ActivoTipo>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tipo == null ? 'Nuevo Tipo' : 'Editar Tipo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre *'),
              autofocus: true,
            ),
            DropdownButtonFormField<int?>(
              initialValue: categoriaId,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Sin categoría'),
                ),
                for (final c in categorias)
                  DropdownMenuItem<int?>(
                    value: c.id,
                    child: Text(c.nombre),
                  ),
              ],
              onChanged: (v) => categoriaId = v,
            ),
            OpcionesField(
              controller: grupoCtrl,
              label: 'Grupo',
              opciones: grupos,
              icono: Icons.create_new_folder_outlined,
            ),
            OpcionesField(
              controller: modeloCtrl,
              label: 'Modelo',
              opciones: modelos,
              icono: Icons.memory_outlined,
            ),
          ],
        ),
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
              ActivoTipo(
                id: tipo?.id ?? 0,
                nombre: nombre,
                grupo: grupoCtrl.text.trim().isEmpty
                    ? null
                    : grupoCtrl.text.trim(),
                modelo: modeloCtrl.text.trim().isEmpty
                    ? null
                    : modeloCtrl.text.trim(),
                categoriaId: categoriaId,
                activo: tipo?.activo ?? true,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}