import 'package:flutter/material.dart';

import '../../../../core/models/almacen.dart';
import '../../data/configuracion_repository.dart';

/// Diálogo para crear o editar un almacén.
/// Devuelve `true` si se guardó correctamente.
Future<bool?> showAlmacenDialog(
  BuildContext context, {
  required ConfiguracionRepository repo,
  Almacen? almacen,
  String? nombreViejo,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _AlmacenDialog(
      repo: repo,
      almacen: almacen,
      nombreViejo: nombreViejo,
    ),
  );
}

class _AlmacenDialog extends StatefulWidget {
  const _AlmacenDialog({
    required this.repo,
    this.almacen,
    this.nombreViejo,
  });

  final ConfiguracionRepository repo;
  final Almacen? almacen;
  final String? nombreViejo;

  @override
  State<_AlmacenDialog> createState() => _AlmacenDialogState();
}

class _AlmacenDialogState extends State<_AlmacenDialog> {
  late final TextEditingController _nombre;
  final TextEditingController _descripcion = TextEditingController();
  late bool _activo;
  final _formKey = GlobalKey<FormState>();
  bool _guardando = false;

  bool get _esEdicion => widget.almacen != null;

  @override
  void initState() {
    super.initState();
    final a = widget.almacen;
    _nombre = TextEditingController(text: a?.nombre ?? '');
    _descripcion.text = a?.descripcion ?? '';
    _activo = a?.activo ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _guardando = true);
    final almacen = Almacen(
      id: widget.almacen?.id ?? 0,
      nombre: _nombre.text.trim(),
      descripcion: _descripcion.text.trim().isEmpty
          ? null
          : _descripcion.text.trim(),
      activo: _activo,
      orden: widget.almacen?.orden ?? 0,
    );
    if (_esEdicion) {
      await widget.repo
          .actualizarAlmacen(almacen, nombreViejo: widget.nombreViejo ?? almacen.nombre);
    } else {
      await widget.repo.crearAlmacen(almacen);
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar almacén' : 'Nuevo almacén'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nombre,
              decoration: const InputDecoration(
                  labelText: 'Nombre', border: OutlineInputBorder(), isDense: true),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Ingrese un nombre'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descripcion,
              decoration: const InputDecoration(
                  labelText: 'Descripción', border: OutlineInputBorder(), isDense: true),
              maxLines: 2,
            ),
            if (_esEdicion) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Activo'),
                  const Spacer(),
                  Switch(value: _activo, onChanged: (v) => setState(() => _activo = v)),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}