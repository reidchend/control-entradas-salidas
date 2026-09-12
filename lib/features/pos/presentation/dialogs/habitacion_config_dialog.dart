import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_models.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../data/pos_providers.dart';

/// Alta/edición de habitación POS (port de `ConfigPOSView._show_agregar_habitacion_dialog`
/// y `_show_editar_habitacion_dialog`). Retorna `true` si se guardó.
Future<bool> showHabitacionConfigDialog(BuildContext context,
    {PosHabitacion? habitacion}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _HabitacionConfigDialog(habitacion: habitacion),
  );
  return ok ?? false;
}

class _HabitacionConfigDialog extends ConsumerStatefulWidget {
  const _HabitacionConfigDialog({this.habitacion});

  final PosHabitacion? habitacion;

  @override
  ConsumerState<_HabitacionConfigDialog> createState() =>
      _HabitacionConfigDialogState();
}

class _HabitacionConfigDialogState
    extends ConsumerState<_HabitacionConfigDialog> {
  final _numeroCtrl = TextEditingController();
  final _pisoCtrl = TextEditingController();
  final _tipoCtrl = TextEditingController();
  bool _guardando = false;

  bool get _esEdicion => widget.habitacion != null;

  @override
  void initState() {
    super.initState();
    final h = widget.habitacion;
    _numeroCtrl.text = h?.numero ?? '';
    _pisoCtrl.text = h?.piso ?? '';
    _tipoCtrl.text = h?.tipo ?? '';
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _pisoCtrl.dispose();
    _tipoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final numero = _numeroCtrl.text.trim();
    if (numero.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese el número de habitación')),
      );
      return;
    }
    setState(() => _guardando = true);
    final repo = ref.read(posRepoProvider)!;
    try {
      if (_esEdicion) {
        await repo.actualizarHabitacion(
          widget.habitacion!.id,
          numero: numero,
          piso: _pisoCtrl.text,
          tipo: _tipoCtrl.text,
        );
      } else {
        await repo.crearHabitacion(numero,
            piso: _pisoCtrl.text, tipo: _tipoCtrl.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar Habitación' : 'Nueva Habitación'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _numeroCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Número de habitación',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pisoCtrl,
              decoration: const InputDecoration(
                labelText: 'Piso (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tipoCtrl,
              decoration: const InputDecoration(
                labelText: 'Tipo (ej: Suite, Estándar)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}
