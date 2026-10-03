import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_models.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../data/pos_providers.dart';
import 'tipos_habitacion_dialog.dart';

/// Alta/edición de habitación POS. El tipo se elige del catálogo
/// `tipos_habitacion` (que define la capacidad de personas). Retorna
/// `true` si se guardó.
Future<bool> showHabitacionConfigDialog(BuildContext context,
    {Habitacion? habitacion}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _HabitacionConfigDialog(habitacion: habitacion),
  );
  return ok ?? false;
}

class _HabitacionConfigDialog extends ConsumerStatefulWidget {
  const _HabitacionConfigDialog({this.habitacion});

  final Habitacion? habitacion;

  @override
  ConsumerState<_HabitacionConfigDialog> createState() =>
      _HabitacionConfigDialogState();
}

class _HabitacionConfigDialogState
    extends ConsumerState<_HabitacionConfigDialog> {
  final _numeroCtrl = TextEditingController();
  final _pisoCtrl = TextEditingController();
  int? _tipoId;
  bool _guardando = false;

  bool get _esEdicion => widget.habitacion != null;

  @override
  void initState() {
    super.initState();
    final h = widget.habitacion;
    _numeroCtrl.text = h?.numero ?? '';
    _pisoCtrl.text = h?.piso ?? '';
    _tipoId = h?.tipoId;
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _pisoCtrl.dispose();
    super.dispose();
  }

  Future<void> _gestionarTipos() async {
    await showTiposHabitacionDialog(context);
    ref.invalidate(tiposHabitacionProvider);
  }

  Future<void> _guardar(List<TipoHabitacion> tipos) async {
    final numero = _numeroCtrl.text.trim();
    if (numero.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese el número de habitación')),
      );
      return;
    }
    if (_tipoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione el tipo de habitación')),
      );
      return;
    }
    final tipo = tipos.firstWhere((t) => t.id == _tipoId);
    setState(() => _guardando = true);
    final repo = ref.read(posRepoProvider)!;
    try {
      if (_esEdicion) {
        await repo.actualizarHabitacion(
          widget.habitacion!.id,
          numero: numero,
          piso: _pisoCtrl.text,
          tipo: tipo.nombre,
          tipoId: tipo.id,
        );
      } else {
        await repo.crearHabitacion(numero,
            piso: _pisoCtrl.text, tipo: tipo.nombre, tipoId: tipo.id);
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
    final tiposAsync = ref.watch(tiposHabitacionProvider);
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar Habitación' : 'Nueva Habitación'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: tiposAsync.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error al cargar tipos: $e'),
          data: (tipos) {
            var seleccionado = _tipoId;
            if (seleccionado == null && _esEdicion) {
              final match = tipos
                  .where((t) => t.nombre == widget.habitacion!.tipo)
                  .toList();
              if (match.isNotEmpty) seleccionado = match.first.id;
            }
            return Column(
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
                DropdownButtonFormField<int>(
                  initialValue: seleccionado,
                  decoration: InputDecoration(
                    labelText: 'Tipo de habitación',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Gestionar tipos',
                      icon: const Icon(Icons.tune),
                      onPressed: _gestionarTipos,
                    ),
                  ),
                  items: [
                    for (final t in tipos)
                      DropdownMenuItem(
                        value: t.id,
                        child: Text('${t.nombre} · ${t.capacidad} pers.'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _tipoId = v),
                ),
                if (tipos.isEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No hay tipos. Cree uno con el botón de la derecha.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        Consumer(
          builder: (context, ref, _) {
            final tipos =
                ref.watch(tiposHabitacionProvider).valueOrNull ?? const [];
            return FilledButton(
              onPressed: _guardando || tipos.isEmpty
                  ? null
                  : () => _guardar(tipos),
              child: Text(_guardando ? 'Guardando…' : 'Guardar'),
            );
          },
        ),
      ],
    );
  }
}
