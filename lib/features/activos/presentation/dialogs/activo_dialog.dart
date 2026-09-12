import 'package:flutter/material.dart';

import '../../data/activo.dart';

const _estados = ['Activo', 'Mantenimiento', 'Baja', 'Reservado', 'Traslado'];

/// Muestra el diálogo crear/editar y devuelve el activo capturado,
/// o `null` si se canceló.
Future<Activo?> showActivoDialog(
  BuildContext context, {
  Activo? activo,
}) async {
  final nombreCtrl = TextEditingController(text: activo?.nombre ?? '');
  final categoriaCtrl =
      TextEditingController(text: activo?.categoria?.trim() ?? '');
  final ubicacionCtrl =
      TextEditingController(text: activo?.ubicacion?.trim() ?? '');
  final estadoValor = (activo?.estado ?? 'Activo').trim().isEmpty
      ? 'Activo'
      : activo!.estado.trim();
  final valorCtrl = TextEditingController(
      text: activo != null && activo.valor > 0
          ? activo.valor.toStringAsFixed(2)
          : '');
  final fechaCtrl = TextEditingController(text: activo?.fecha ?? '');
  final grupoCtrl = TextEditingController(text: activo?.grupo?.trim() ?? '');
  final modeloCtrl = TextEditingController(text: activo?.modelo?.trim() ?? '');
  final cantidadCtrl =
      TextEditingController(text: (activo?.cantidad ?? 1).toString());
  final obsCtrl =
      TextEditingController(text: activo?.observaciones?.trim() ?? '');
  var estadoSeleccionado = estadoValor;

  return showDialog<Activo>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(activo == null ? 'Nuevo Activo' : 'Editar Activo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre *'),
              autofocus: true,
            ),
            TextField(
              controller: categoriaCtrl,
              decoration: const InputDecoration(labelText: 'Categoría'),
            ),
            TextField(
              controller: ubicacionCtrl,
              decoration: const InputDecoration(labelText: 'Ubicación'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _estados.contains(estadoValor)
                  ? estadoValor
                  : _estados.first,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: [
                if (!_estados.contains(estadoValor))
                  DropdownMenuItem(
                    value: estadoValor,
                    child: Text(estadoValor),
                  ),
                for (final s in _estados)
                  DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) => estadoSeleccionado = v ?? estadoValor,
            ),
            TextField(
              controller: valorCtrl,
              decoration: const InputDecoration(labelText: 'Valor (Bs)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: fechaCtrl,
              decoration: const InputDecoration(
                labelText: 'Fecha (AAAA-MM-DD)',
                hintText: '2025-01-15',
              ),
            ),
            TextField(
              controller: grupoCtrl,
              decoration: const InputDecoration(labelText: 'Grupo'),
            ),
            TextField(
              controller: modeloCtrl,
              decoration: const InputDecoration(labelText: 'Modelo'),
            ),
            TextField(
              controller: cantidadCtrl,
              decoration: const InputDecoration(labelText: 'Cantidad'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: obsCtrl,
              decoration: const InputDecoration(labelText: 'Observaciones'),
              maxLines: 2,
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
              Activo(
                id: activo?.id ?? 0,
                nombre: nombre,
                categoria: categoriaCtrl.text.trim().isEmpty
                    ? null
                    : categoriaCtrl.text.trim(),
                ubicacion: ubicacionCtrl.text.trim().isEmpty
                    ? null
                    : ubicacionCtrl.text.trim(),
                estado: estadoSeleccionado,
                valor: double.tryParse(valorCtrl.text.trim()) ?? 0,
                fecha: fechaCtrl.text.trim().isEmpty
                    ? null
                    : fechaCtrl.text.trim(),
                observaciones: obsCtrl.text.trim().isEmpty
                    ? null
                    : obsCtrl.text.trim(),
                grupo: grupoCtrl.text.trim().isEmpty
                    ? null
                    : grupoCtrl.text.trim(),
                modelo: modeloCtrl.text.trim().isEmpty
                    ? null
                    : modeloCtrl.text.trim(),
                cantidad: int.tryParse(cantidadCtrl.text.trim()) ?? 1,
                activo: activo?.activo ?? true,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}