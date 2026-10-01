import 'package:flutter/material.dart';

/// Campo editable con autocompletado de valores existentes.
///
/// Sirve para propiedades que se repiten (ubicación, grupo, modelo) y también
/// para objetos con identidad propia, como los tipos de activo: en ese caso
/// [textoDe] arma la etiqueta y el `RawAutocomplete` la usa tanto para filtrar
/// como para rellenar el campo al elegir.
///
/// [textoDe] no es opcional a propósito: `RawAutocomplete` usa
/// `displayStringForOption` para escribir la opción elegida, y su valor por
/// defecto es `o.toString()`, que para un objeto imprimiría
/// `Instance of 'MiClase'`.
///
/// El `extends Object` en [T] es obligatorio: `RawAutocomplete` declara
/// `T extends Object` y sin el límite el compilador lo rechaza.
class OpcionesField<T extends Object> extends StatelessWidget {
  const OpcionesField({
    super.key,
    required this.controller,
    required this.label,
    required this.opciones,
    required this.textoDe,
    required this.icono,
    this.focusNode,
    this.hintText,
  });

  final TextEditingController controller;
  final String label;
  final List<T> opciones;
  final String Function(T) textoDe;
  final IconData icono;
  final FocusNode? focusNode;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<T>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: textoDe,
      optionsBuilder: (TextEditingValue tev) {
        if (opciones.isEmpty) return <T>[];
        final q = tev.text.trim().toLowerCase();
        if (q.isEmpty) return opciones;
        return opciones
            .where((o) => textoDe(o).toLowerCase().contains(q))
            .toList();
      },
      // El framework ya copia la opción al controller en `_select`; este
      // callback queda para el consumidor que necesite reaccionar.
      onSelected: (_) {},
      fieldViewBuilder: (context, tc, focusNode, onFieldSubmitted) => TextField(
        controller: tc,
        focusNode: focusNode,
        onSubmitted: (_) => onFieldSubmitted(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText ?? 'Elige uno existente o escribe uno nuevo',
          suffixIcon: Icon(icono),
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final o = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(textoDe(o)),
                    onTap: () => onSelected(o),
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
