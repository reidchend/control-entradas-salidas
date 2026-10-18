import 'package:flutter/material.dart';

/// Barra de filtros con rango de fechas (Desde/Hasta) y botón de actualizar.
/// En pantallas anchas va en fila; en móviles, apilado y a ancho completo.
class FiltroRangoFechas extends StatelessWidget {
  const FiltroRangoFechas({
    super.key,
    required this.desde,
    required this.hasta,
    required this.onDesdeChanged,
    required this.onHastaChanged,
    required this.onActualizar,
    required this.esMovil,
    this.actualizando = false,
    this.etiquetaAccion = 'Actualizar',
  });

  final DateTime desde;
  final DateTime hasta;
  final ValueChanged<DateTime> onDesdeChanged;
  final ValueChanged<DateTime> onHastaChanged;
  final VoidCallback onActualizar;

  /// `true` apila los controles y los estira a ancho completo (móvil).
  final bool esMovil;

  /// Si es `true`, el botón de acción queda deshabilitado.
  final bool actualizando;

  /// Texto del botón de acción (ej. "Actualizar KPIs").
  final String etiquetaAccion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accion = FilledButton.icon(
      icon: const Icon(Icons.refresh, size: 18),
      label: Text(etiquetaAccion),
      onPressed: actualizando ? null : onActualizar,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: esMovil
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _DatePicker(
                        label: 'Desde',
                        value: desde,
                        onChanged: onDesdeChanged,
                        width: double.infinity,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DatePicker(
                        label: 'Hasta',
                        value: hasta,
                        onChanged: onHastaChanged,
                        width: double.infinity,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                accion,
              ],
            )
          : Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _DatePicker(label: 'Desde', value: desde, onChanged: onDesdeChanged),
                _DatePicker(label: 'Hasta', value: hasta, onChanged: onHastaChanged),
                accion,
              ],
            ),
    );
  }
}

class _DatePicker extends StatelessWidget {
  const _DatePicker({
    required this.label,
    required this.value,
    required this.onChanged,
    this.width,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? 160,
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 1)),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
          ),
          child: Text(
            '${value.day.toString().padLeft(2, '0')}/'
            '${value.month.toString().padLeft(2, '0')}/${value.year}',
          ),
        ),
      ),
    );
  }
}
