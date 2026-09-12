import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_models.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../data/pos_providers.dart';

/// Alta/edición de categoría POS (port de `ConfigPOSView._show_pos_categoria_dialog`).
/// Retorna `true` si se guardó.
Future<bool> showPosCategoriaDialog(BuildContext context,
    {PosCategoria? categoria}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _PosCategoriaDialog(categoria: categoria),
  );
  return ok ?? false;
}

class _PosCategoriaDialog extends ConsumerStatefulWidget {
  const _PosCategoriaDialog({this.categoria});

  final PosCategoria? categoria;

  @override
  ConsumerState<_PosCategoriaDialog> createState() =>
      _PosCategoriaDialogState();
}

class _PosCategoriaDialogState extends ConsumerState<_PosCategoriaDialog> {
  static const _colores = [
    ('#FF6F00', 'Naranja'),
    ('#E53935', 'Rojo'),
    ('#43A047', 'Verde'),
    ('#1E88E5', 'Azul'),
    ('#8E24AA', 'Morado'),
    ('#00ACC1', 'Cyan'),
  ];

  final _nombreCtrl = TextEditingController();
  final _iconoCtrl = TextEditingController();
  late String _color;
  bool _guardando = false;

  bool get _esEdicion => widget.categoria != null;

  @override
  void initState() {
    super.initState();
    final c = widget.categoria;
    _nombreCtrl.text = c?.nombre ?? '';
    _iconoCtrl.text = c?.icono ?? '';
    _color = c?.color ?? '#FF6F00';
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _iconoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese el nombre')),
      );
      return;
    }
    setState(() => _guardando = true);
    final repo = ref.read(posRepoProvider)!;
    try {
      if (_esEdicion) {
        await repo.actualizarPosCategoria(
          widget.categoria!.id,
          nombre,
          color: _color,
          icono: _iconoCtrl.text.trim().isEmpty
              ? null
              : _iconoCtrl.text.trim(),
        );
      } else {
        await repo.crearPosCategoria(nombre,
            color: _color,
            icono:
                _iconoCtrl.text.trim().isEmpty ? null : _iconoCtrl.text.trim());
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
      title: Text(_esEdicion ? 'Editar categoría POS' : 'Nueva categoría POS'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nombreCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _color,
                    decoration: const InputDecoration(
                      labelText: 'Color',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in _colores)
                        DropdownMenuItem(
                          value: c.$1,
                          child: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: _hex(c.$1),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(c.$2),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _color = v ?? _color),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _iconoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Icono (opcional)',
                      hintText: 'ej: restaurant',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
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

Color _hex(String value) {
  final v = value.replaceFirst('#', '');
  return Color(int.parse('FF$v', radix: 16));
}
