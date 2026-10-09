import 'package:flutter/material.dart';

import '../../../../core/models/producto.dart' as domain;

/// Campo de producto con búsqueda, para elegir el insumo de un ingrediente.
///
/// Mismo comportamiento que el selector de tipo de activos: se escribe para
/// filtrar y se elige de la lista. Reemplaza al desplegable, que con decenas
/// de insumos se hacía largo de recorrer y no permitía filtrar.
class ProductoSelectorField extends StatelessWidget {
  const ProductoSelectorField({
    super.key,
    required this.controller,
    required this.productos,
    required this.onSelected,
    this.errorText,
  });

  final TextEditingController controller;
  final List<domain.Producto> productos;
  final ValueChanged<domain.Producto> onSelected;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<domain.Producto>(
      textEditingController: controller,
      // Sin esto el framework escribiría `Instance of 'Producto'` al elegir.
      displayStringForOption: (p) => p.nombre,
      optionsBuilder: (TextEditingValue tev) {
        if (productos.isEmpty) return <domain.Producto>[];
        final q = tev.text.trim().toLowerCase();
        if (q.isEmpty) return productos;
        return productos.where((p) => p.nombre.toLowerCase().contains(q)).toList();
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, tc, focusNode, onFieldSubmitted) => TextField(
        controller: tc,
        focusNode: focusNode,
        onSubmitted: (_) => onFieldSubmitted(),
        decoration: InputDecoration(
          labelText: 'Producto',
          hintText: productos.isEmpty
              ? 'No hay insumos cargados'
              : 'Escribí para filtrar o elegí de la lista',
          border: const OutlineInputBorder(),
          isDense: true,
          errorText: errorText,
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final p = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.inventory_2_outlined, size: 18),
                    title: Text(
                      p.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(p.unidadMedida),
                    onTap: () => onSelected(p),
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
