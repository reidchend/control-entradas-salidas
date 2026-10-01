import 'package:flutter/material.dart';

/// Campo de texto con etiqueta, para las columnas del formulario de activos.
///
/// Existe sólo para no repetir la misma decoración en valor, fecha y
/// observaciones: los tres cambian poco más que el teclado y cuántas líneas
/// admiten.
class ActivoCampoTexto extends StatelessWidget {
  const ActivoCampoTexto({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.keyboardType,
    this.minLines,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final TextInputType? keyboardType;
  final int? minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, hintText: hintText),
    );
  }
}

/// Fila informativa del tipo fijo (no editable).
///
/// Aparece al agregar o editar desde el detalle de un tipo, donde el tipo ya
/// está decidido y sólo queda mostrarlo.
class ActivoFilaTipoFijo extends StatelessWidget {
  const ActivoFilaTipoFijo({super.key, required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nombre,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de acciones del formulario.
///
/// Va dentro del contenido y no en el `AppBar` ni en el `actions` del diálogo
/// para que sea la misma en los dos casos: la pantalla y el diálogo comparten
/// este formulario entero.
class ActivoAcciones extends StatelessWidget {
  const ActivoAcciones({
    super.key,
    required this.guardando,
    required this.onCancelar,
    required this.onGuardar,
  });

  final bool guardando;
  final VoidCallback onCancelar;
  final VoidCallback onGuardar;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: guardando ? null : onCancelar,
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: guardando ? null : onGuardar,
          child: guardando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
