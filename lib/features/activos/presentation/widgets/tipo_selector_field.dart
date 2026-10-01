import 'package:flutter/material.dart';

import '../../data/activo_tipo.dart';

/// Modelo y grupo del tipo, omitiendo los que estén vacíos.
List<String> _detalle(ActivoTipo t) => [
      if ((t.modelo ?? '').trim().isNotEmpty) t.modelo!.trim(),
      if ((t.grupo ?? '').trim().isNotEmpty) t.grupo!.trim(),
    ];

/// Etiqueta legible de un tipo: nombre más modelo y grupo cuando existen.
///
/// Se usa para filtrar, para las filas de la lista y para lo que queda escrito
/// en el campo al elegir uno, así que vive acá y no duplicada en cada pantalla.
String textoTipo(ActivoTipo t) {
  final d = _detalle(t);
  return d.isEmpty ? t.nombre : '${t.nombre} · ${d.join(' · ')}';
}

/// Subtítulo de la fila de la lista: el detalle sin repetir el nombre, que ya
/// está en el título.
String? detalleTipo(ActivoTipo t) {
  final d = _detalle(t);
  return d.isEmpty ? null : d.join(' · ');
}

/// Campo de tipo con búsqueda, mezclando lista desplegable y escritura.
///
/// Reemplaza al `DropdownButtonFormField`: con muchos tipos la lista se hace
/// larga de recorrer y no había forma de filtrar sin usar el scroll. Acá se
/// escribe para filtrar y se elige de la lista, igual que el campo de ubicación.
///
/// Si [onCrearNuevo] viene, muestra un botón para dar de alta un tipo que no
/// existe todavía, en vez de la opción "＋ Nuevo tipo..." del dropdown.
class TipoSelectorField extends StatelessWidget {
  const TipoSelectorField({
    super.key,
    required this.controller,
    required this.tipos,
    required this.onSelected,
    this.onCrearNuevo,
    this.errorText,
  });

  final TextEditingController controller;
  final List<ActivoTipo> tipos;
  final ValueChanged<ActivoTipo> onSelected;
  final VoidCallback? onCrearNuevo;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<ActivoTipo>(
      textEditingController: controller,
      // Sin esto el framework escribiría `Instance of 'ActivoTipo'` al elegir.
      displayStringForOption: textoTipo,
      optionsBuilder: (TextEditingValue tev) {
        if (tipos.isEmpty) return <ActivoTipo>[];
        final q = tev.text.trim().toLowerCase();
        if (q.isEmpty) return tipos;
        return tipos
            .where((t) => textoTipo(t).toLowerCase().contains(q))
            .toList();
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, tc, focusNode, onFieldSubmitted) => TextField(
        controller: tc,
        focusNode: focusNode,
        onSubmitted: (_) => onFieldSubmitted(),
        decoration: InputDecoration(
          labelText: 'Tipo *',
          hintText: tipos.isEmpty
              ? 'No hay tipos: creá el primero'
              : 'Escribí para filtrar o elegí de la lista',
          errorText: errorText,
          suffixIcon: onCrearNuevo == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Crear tipo nuevo',
                  onPressed: onCrearNuevo,
                ),
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final t = options.elementAt(i);
                  final detalle = detalleTipo(t);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.inventory_2_outlined, size: 18),
                    title: Text(
                      t.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: detalle == null ? null : Text(detalle),
                    onTap: () => onSelected(t),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
