import 'package:flutter/material.dart';

import '../widgets/cantidad_stepper.dart';
import '../widgets/opciones_field.dart';

/// Resultado del diálogo de mover: cuántas unidades y a dónde.
class MovimientoUnidades {
  const MovimientoUnidades({required this.cantidad, required this.ubicacion});

  final int cantidad;

  /// `null` o vacío significa dejarlas sin ubicación.
  final String? ubicacion;
}

/// Pide cuántas unidades mover y la ubicación de destino.
///
/// [codigos] viene del grupo, de la más nueva a la más vieja: se mueven las
/// primeras [cantidad] para conservar las placas más antiguas.
Future<MovimientoUnidades?> showMoverUnidadesDialog(
  BuildContext context, {
  required int cantidad,
  required String? ubicacionActual,
  required List<String> ubicaciones,
  required List<String> codigos,
}) {
  return showDialog<MovimientoUnidades>(
    context: context,
    builder: (_) => _MoverDialog(
      cantidad: cantidad,
      ubicacionActual: ubicacionActual,
      ubicaciones: ubicaciones,
      codigos: codigos,
    ),
  );
}

class _MoverDialog extends StatefulWidget {
  const _MoverDialog({
    required this.cantidad,
    required this.ubicacionActual,
    required this.ubicaciones,
    required this.codigos,
  });

  final int cantidad;
  final String? ubicacionActual;
  final List<String> ubicaciones;
  final List<String> codigos;

  @override
  State<_MoverDialog> createState() => _MoverDialogState();
}

class _MoverDialogState extends State<_MoverDialog> {
  late final TextEditingController _cantidadCtrl =
      TextEditingController(text: '${widget.cantidad}');
  late final TextEditingController _destinoCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    _destinoCtrl.dispose();
    super.dispose();
  }

  int get _cantidad {
    final n = int.tryParse(_cantidadCtrl.text.trim()) ?? widget.cantidad;
    return n.clamp(1, widget.cantidad);
  }

  void _mover() {
    final destino = _destinoCtrl.text.trim();
    final actual = (widget.ubicacionActual ?? '').trim();
    if (destino == actual) {
      setState(() => _error = 'Elegí una ubicación distinta a la actual');
      return;
    }
    Navigator.pop(
      context,
      MovimientoUnidades(
        cantidad: _cantidad,
        ubicacion: destino.isEmpty ? null : destino,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final actual = (widget.ubicacionActual ?? '').trim();
    final sugerencias = [
      for (final u in widget.ubicaciones)
        if (u.trim() != actual) u,
    ];

    return AlertDialog(
      title: const Text('Mover unidades'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                actual.isEmpty
                    ? 'Ahora están sin ubicación.'
                    : 'Ahora están en «$actual».',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              CantidadStepper(
                controller: _cantidadCtrl,
                label: 'Cuántas mover',
                max: widget.cantidad,
                helperText: 'De ${widget.cantidad} en total',
              ),
              const SizedBox(height: 12),
              OpcionesField<String>(
                controller: _destinoCtrl,
                label: 'Ubicación destino',
                opciones: sugerencias,
                textoDe: (s) => s,
                icono: Icons.place_outlined,
                hintText: 'Elegí una existente o escribí una nueva',
              ),
              const SizedBox(height: 6),
              Text(
                'Vacío = sin ubicación.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _cantidadCtrl,
                builder: (context, value, _) {
                  final n = int.tryParse(value.text.trim()) ?? widget.cantidad;
                  final seleccion =
                      widget.codigos.take(n.clamp(1, widget.cantidad)).toList();
                  if (seleccion.isEmpty) return const SizedBox.shrink();
                  final resumen = seleccion.length == 1
                      ? seleccion.first
                      : '${seleccion.last} … ${seleccion.first}';
                  return Text(
                    'Se mueven ${seleccion.length} '
                    '${seleccion.length == 1 ? 'unidad' : 'unidades'}: $resumen',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _mover,
          icon: const Icon(Icons.drive_file_move_outlined),
          label: const Text('Mover'),
        ),
      ],
    );
  }
}
