import 'package:flutter/material.dart';

import '../../../../core/models/categoria.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../data/configuracion_repository.dart';

/// Diálogo para crear/editar una Categoría (porta `show_categoria_dialog`).
Future<bool?> showCategoriaDialog(
  BuildContext context,
  ConfiguracionRepository repo, {
  Categoria? categoria,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _CategoriaDialog(repo: repo, categoria: categoria),
  );
}

class _CategoriaDialog extends StatefulWidget {
  const _CategoriaDialog({required this.repo, this.categoria});

  final ConfiguracionRepository repo;
  final Categoria? categoria;

  @override
  State<_CategoriaDialog> createState() => _CategoriaDialogState();
}

class _CategoriaDialogState extends State<_CategoriaDialog> {
  final _nombreCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  bool _activo = true;
  bool _visibleEnPos = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    if (widget.categoria != null) {
      final c = widget.categoria!;
      _nombreCtrl.text = c.nombre;
      _descripcionCtrl.text = c.descripcion ?? '';
      _colorCtrl.text = c.color;
      _activo = c.activo;
      _visibleEnPos = c.visibleEnPos;
    } else {
      _colorCtrl.text = '#2196F3';
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.categoria != null;

    return AlertDialog(
      title: Text(esEdicion ? 'Editar Categoría' : 'Nueva Categoría'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: modalContentWidth(context)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descripcionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _colorCtrl,
                decoration: InputDecoration(
                  labelText: 'Color (Hex) *',
                  hintText: '#2196F3',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: _ColorPickerButton(controller: _colorCtrl),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SwitchListTile(
                      title: const Text('Activo'),
                      value: _activo,
                      onChanged: (v) => setState(() => _activo = v),
                      dense: true,
                    ),
                  ),
                  Expanded(
                    child: SwitchListTile(
                      title: const Text('Visible en POS'),
                      value: _visibleEnPos,
                      onChanged: (v) => setState(() => _visibleEnPos = v),
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando || _nombreCtrl.text.trim().isEmpty ? null : _guardar,
          child: _guardando
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) return;

    setState(() => _guardando = true);
    try {
      final data = <String, dynamic>{
        'nombre': nombre,
        'descripcion': _descripcionCtrl.text.trim().isEmpty ? null : _descripcionCtrl.text.trim(),
        'color': _colorCtrl.text.trim(),
        'activo': _activo,
        'visible_en_pos': _visibleEnPos,
      };

      if (widget.categoria != null) {
        await widget.repo.updateCategoria(widget.categoria!.id, data);
      } else {
        await widget.repo.createCategoria(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }
}

class _ColorPickerButton extends StatelessWidget {
  const _ColorPickerButton({required this.controller});

  final TextEditingController controller;

  static const _presets = [
    '#2196F3', '#4CAF50', '#FF9800', '#F44336', '#9C27B0',
    '#00BCD4', '#795548', '#607D8B', '#E91E63', '#FFEB3B',
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _parseColor(controller.text),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade400),
        ),
      ),
      onSelected: (color) => controller.text = color,
      itemBuilder: (ctx) => _presets.map((c) {
        return PopupMenuItem<String>(
          value: c,
          child: Row(
            children: [
              Container(width: 16, height: 16, color: _parseColor(c), margin: const EdgeInsets.only(right: 8)),
              Text(c),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.blue;
    }
  }
}
