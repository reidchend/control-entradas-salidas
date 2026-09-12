import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_models.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../data/pos_providers.dart';

/// Alta/edición de mesa POS (port de `ConfigPOSView._show_agregar_mesa_dialog`
/// y `_show_editar_mesa_dialog`). Retorna `true` si se guardó.
Future<bool> showMesaConfigDialog(BuildContext context, {PosMesa? mesa}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _MesaConfigDialog(mesa: mesa),
  );
  return ok ?? false;
}

class _MesaConfigDialog extends ConsumerStatefulWidget {
  const _MesaConfigDialog({this.mesa});

  final PosMesa? mesa;

  @override
  ConsumerState<_MesaConfigDialog> createState() => _MesaConfigDialogState();
}

class _MesaConfigDialogState extends ConsumerState<_MesaConfigDialog> {
  final _numeroCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _zonaCtrl = TextEditingController();
  bool _guardando = false;

  bool get _esEdicion => widget.mesa != null;

  @override
  void initState() {
    super.initState();
    final m = widget.mesa;
    _numeroCtrl.text = m?.numero ?? '';
    _nombreCtrl.text = m?.nombre ?? '';
    _zonaCtrl.text = m?.zona ?? '';
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _nombreCtrl.dispose();
    _zonaCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final numero = _numeroCtrl.text.trim();
    if (numero.isEmpty) {
      _numeroCtrl.text = ' ';
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese el número de mesa')),
      );
      return;
    }
    setState(() => _guardando = true);
    final repo = ref.read(posRepoProvider)!;
    try {
      if (_esEdicion) {
        await repo.actualizarMesa(
          widget.mesa!.id,
          numero: numero,
          nombre: _nombreCtrl.text,
          zona: _zonaCtrl.text,
        );
      } else {
        await repo.crearMesa(numero,
            nombre: _nombreCtrl.text, zona: _zonaCtrl.text);
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
      title: Text(_esEdicion ? 'Editar Mesa' : 'Nueva Mesa'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _numeroCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Número de mesa',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _zonaCtrl,
              decoration: const InputDecoration(
                labelText: 'Zona (opcional)',
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
