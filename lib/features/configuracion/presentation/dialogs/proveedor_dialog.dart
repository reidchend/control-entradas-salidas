import 'package:flutter/material.dart';

import '../../../../core/models/proveedor.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../data/configuracion_repository.dart';

/// Diálogo para crear/editar un Proveedor (porta `show_proveedor_dialog` / dialogs.py).
Future<bool?> showProveedorDialog(
  BuildContext context,
  ConfiguracionRepository repo, {
  Proveedor? proveedor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _ProveedorDialog(repo: repo, proveedor: proveedor),
  );
}

class _ProveedorDialog extends StatefulWidget {
  const _ProveedorDialog({required this.repo, this.proveedor});

  final ConfiguracionRepository repo;
  final Proveedor? proveedor;

  @override
  State<_ProveedorDialog> createState() => _ProveedorDialogState();
}

class _ProveedorDialogState extends State<_ProveedorDialog> {
  final _nombreCtrl = TextEditingController();
  final _rifCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _contactoCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  String _estado = 'Activo';
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    if (widget.proveedor != null) {
      final p = widget.proveedor!;
      _nombreCtrl.text = p.nombre;
      _rifCtrl.text = p.rif ?? '';
      _telefonoCtrl.text = p.telefono ?? '';
      _emailCtrl.text = p.email ?? '';
      _direccionCtrl.text = p.direccion ?? '';
      _contactoCtrl.text = p.contacto ?? '';
      _observacionesCtrl.text = p.observaciones ?? '';
      _estado = p.estado;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _rifCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _direccionCtrl.dispose();
    _contactoCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.proveedor != null;

    return AlertDialog(
      title: Text(esEdicion ? 'Editar Proveedor' : 'Nuevo Proveedor'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: modalContentWidth(context), maxHeight: 600),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *', border: OutlineInputBorder(), isDense: true),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rifCtrl,
                decoration: const InputDecoration(labelText: 'RIF (J-12345678-9)', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _telefonoCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), isDense: true),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _direccionCtrl,
                decoration: const InputDecoration(labelText: 'Dirección', border: OutlineInputBorder(), isDense: true),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contactoCtrl,
                decoration: const InputDecoration(labelText: 'Persona de contacto', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _observacionesCtrl,
                decoration: const InputDecoration(labelText: 'Observaciones', border: OutlineInputBorder(), isDense: true),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _estado,
                decoration: const InputDecoration(labelText: 'Estado', border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 'Activo', child: Text('Activo')),
                  DropdownMenuItem(value: 'Inactivo', child: Text('Inactivo')),
                ],
                onChanged: (v) => setState(() => _estado = v ?? 'Activo'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
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
        'rif': _rifCtrl.text.trim().isEmpty ? null : _rifCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim().isEmpty ? null : _telefonoCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'direccion': _direccionCtrl.text.trim().isEmpty ? null : _direccionCtrl.text.trim(),
        'contacto': _contactoCtrl.text.trim().isEmpty ? null : _contactoCtrl.text.trim(),
        'observaciones': _observacionesCtrl.text.trim().isEmpty ? null : _observacionesCtrl.text.trim(),
        'estado': _estado,
      };

      if (widget.proveedor != null) {
        await widget.repo.updateProveedor(widget.proveedor!.id, data);
      } else {
        await widget.repo.createProveedor(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }
}
