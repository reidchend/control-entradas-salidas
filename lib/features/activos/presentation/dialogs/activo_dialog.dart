import 'package:flutter/material.dart';

import '../../data/activo.dart';
import '../../data/activos_categoria.dart';

const _estados = ['Activo', 'Mantenimiento', 'Baja', 'Reservado', 'Traslado'];

/// Muestra el diálogo crear/editar y devuelve el activo capturado,
/// o `null` si se canceló. [categorias] alimenta el selector de categoría.
Future<Activo?> showActivoDialog(
  BuildContext context, {
  Activo? activo,
  List<ActivosCategoria> categorias = const [],
  List<String> grupos = const [],
}) async {
  final nombreCtrl = TextEditingController(text: activo?.nombre ?? '');
  final categoriaIdSeleccionada = activo?.categoriaId;
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
  final grupoFocus = FocusNode();
  final modeloCtrl = TextEditingController(text: activo?.modelo?.trim() ?? '');
  final cantidadCtrl =
      TextEditingController(text: (activo?.cantidad ?? 1).toString());
  final obsCtrl =
      TextEditingController(text: activo?.observaciones?.trim() ?? '');
  var estadoSeleccionado = estadoValor;
  var categoriaId = categoriaIdSeleccionada;

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
            DropdownButtonFormField<int?>(
              value: categoriaId,
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
            TextField(
              controller: ubicacionCtrl,
              decoration: const InputDecoration(labelText: 'Ubicación'),
            ),
            RawAutocomplete<String>(
              textEditingController: grupoCtrl,
              focusNode: grupoFocus,
              optionsBuilder: (TextEditingValue tev) {
                if (grupos.isEmpty || tev.text.isEmpty) return const <String>[];
                final q = tev.text.toLowerCase();
                return grupos.where((g) => g.toLowerCase().contains(q)).toList();
              },
              onSelected: (_) {},
              fieldViewBuilder:
                  (context, tc, focusNode, onFieldSubmitted) => TextField(
                controller: tc,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  labelText: 'Grupo',
                  hintText: 'Escribe uno nuevo o elige uno existente',
                  suffixIcon: Icon(Icons.create_new_folder_outlined),
                ),
              ),
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: options.length,
                        itemBuilder: (context, i) {
                          final g = options.elementAt(i);
                          return ListTile(
                            dense: true,
                            title: Text(g),
                            onTap: () => onSelected(g),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            DropdownButtonFormField<String>(
              value: _estados.contains(estadoValor)
                  ? _estados.first
                  : estadoValor,
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
                categoriaId: categoriaId,
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