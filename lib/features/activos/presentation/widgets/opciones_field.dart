import 'package:flutter/material.dart';

/// Campo editable con autocompletado de los valores existentes de una
/// propiedad (ubicación, grupo, modelo...). Soporta escribir un valor nuevo.
class OpcionesField extends StatelessWidget {
  const OpcionesField({
    super.key,
    required this.controller,
    required this.label,
    required this.opciones,
    required this.icono,
    this.focusNode,
    this.hintText,
  });

  final TextEditingController controller;
  final String label;
  final List<String> opciones;
  final IconData icono;
  final FocusNode? focusNode;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (TextEditingValue tev) {
        if (opciones.isEmpty) return const <String>[];
        final q = tev.text.toLowerCase();
        if (q.isEmpty) return opciones;
        return opciones.where((o) => o.toLowerCase().contains(q)).toList();
      },
      onSelected: (_) {},
      fieldViewBuilder: (context, tc, focusNode, onFieldSubmitted) => TextField(
        controller: tc,
        focusNode: focusNode,
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
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final o = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(o),
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