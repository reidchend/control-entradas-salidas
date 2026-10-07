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

/// Campo de fecha con selector de calendario.
///
/// Reemplaza la escritura a mano de `AAAA-MM-DD`: el `showDatePicker` deja la
/// fecha ya en el formato que espera la base y evita errores de tipeo que
/// entraban sin validación real.
class ActivoCampoFecha extends StatelessWidget {
  const ActivoCampoFecha({super.key, required this.controller, this.label});

  final TextEditingController controller;
  final String? label;

  Future<void> _elegir(BuildContext context) async {
    final actual = _parse(controller.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (picked == null) return;
    controller.text = _formato(picked);
  }

  static DateTime? _parse(String s) {
    final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
    if (m == null) return null;
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    if (y == null || mo == null || d == null) return null;
    return DateTime(y, mo, d);
  }

  static String _formato(DateTime d) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: () => _elegir(context),
      decoration: InputDecoration(
        labelText: label,
        hintText: 'AAAA-MM-DD',
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          tooltip: 'Elegir fecha',
          onPressed: () => _elegir(context),
        ),
      ),
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
/// este formulario entero. Con [lote] (alta de una unidad nueva) se ofrece el
/// toggle "guardar y agregar otra", que deja el formulario abierto para seguir
/// agregando.
class ActivoAcciones extends StatelessWidget {
  const ActivoAcciones({
    super.key,
    required this.guardando,
    required this.onCancelar,
    required this.onGuardar,
    this.lote = false,
    this.agregarOtro = false,
    this.onToggleAgregarOtro,
  });

  final bool guardando;
  final VoidCallback onCancelar;
  final VoidCallback onGuardar;
  final bool lote;
  final bool agregarOtro;
  final ValueChanged<bool?>? onToggleAgregarOtro;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (lote)
          Expanded(
            child: CheckboxListTile(
              value: agregarOtro,
              onChanged: guardando ? null : onToggleAgregarOtro,
              title: const Text(
                'Guardar y agregar otra',
                style: TextStyle(fontSize: 13),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
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
