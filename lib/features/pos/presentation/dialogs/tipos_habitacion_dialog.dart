import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_models.dart';
import '../../data/pos_providers.dart';

/// Gestión del catálogo de tipos de habitación (`tipos_habitacion`):
/// nombre + capacidad máxima de personas.
Future<void> showTiposHabitacionDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _TiposHabitacionDialog(),
  );
}

class _TiposHabitacionDialog extends ConsumerStatefulWidget {
  const _TiposHabitacionDialog();

  @override
  ConsumerState<_TiposHabitacionDialog> createState() =>
      _TiposHabitacionDialogState();
}

class _TiposHabitacionDialogState
    extends ConsumerState<_TiposHabitacionDialog> {
  List<TipoHabitacion> _tipos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final repo = ref.read(posRepoProvider);
    if (repo == null) return;
    final tipos = await repo.getTiposHabitacion();
    if (!mounted) return;
    setState(() {
      _tipos = tipos;
      _cargando = false;
    });
  }

  Future<void> _nuevo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _TipoFormDialog(),
    );
    if (ok == true) {
      ref.invalidate(tiposHabitacionProvider);
      await _cargar();
    }
  }

  Future<void> _editar(TipoHabitacion t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _TipoFormDialog(tipo: t),
    );
    if (ok == true) {
      ref.invalidate(tiposHabitacionProvider);
      await _cargar();
    }
  }

  Future<void> _eliminar(TipoHabitacion t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar tipo'),
        content: Text("¿Eliminar el tipo '${t.nombre}'? "
            'Las habitaciones que lo usen quedarán sin tipo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF5350)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(posRepoProvider)!.eliminarTipoHabitacion(t.id);
    ref.invalidate(tiposHabitacionProvider);
    ref.invalidate(habitacionesProvider);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Tipos de habitación'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _tipos.isEmpty
                ? Center(
                    child: Text('Sin tipos registrados',
                        style: TextStyle(color: scheme.outline)))
                : ListView(
                    children: [
                      for (final t in _tipos)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.nombre),
                          subtitle: Text(
                              'Capacidad: ${t.capacidad} persona(s)'
                              '${t.activo ? '' : ' · inactivo'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editar(t),
                              ),
                              IconButton(
                                tooltip: 'Eliminar',
                                icon: const Icon(Icons.delete_outline,
                                    color: Color(0xFFEF5350)),
                                onPressed: () => _eliminar(t),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          onPressed: _nuevo,
          icon: const Icon(Icons.add),
          label: const Text('Nuevo tipo'),
        ),
      ],
    );
  }
}

class _TipoFormDialog extends ConsumerStatefulWidget {
  const _TipoFormDialog({this.tipo});
  final TipoHabitacion? tipo;

  @override
  ConsumerState<_TipoFormDialog> createState() => _TipoFormDialogState();
}

class _TipoFormDialogState extends ConsumerState<_TipoFormDialog> {
  final _nombreCtrl = TextEditingController();
  final _capacidadCtrl = TextEditingController(text: '1');
  bool _guardando = false;
  String _error = '';

  bool get _esEdicion => widget.tipo != null;

  @override
  void initState() {
    super.initState();
    if (_esEdicion) {
      _nombreCtrl.text = widget.tipo!.nombre;
      _capacidadCtrl.text = '${widget.tipo!.capacidad}';
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _capacidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final capacidad = int.tryParse(_capacidadCtrl.text.trim()) ?? 0;
    if (nombre.isEmpty) {
      setState(() => _error = 'Ingrese el nombre del tipo');
      return;
    }
    if (capacidad < 1) {
      setState(() => _error = 'La capacidad debe ser al menos 1');
      return;
    }
    setState(() {
      _guardando = true;
      _error = '';
    });
    try {
      final repo = ref.read(posRepoProvider)!;
      if (_esEdicion) {
        await repo.actualizarTipoHabitacion(widget.tipo!.id,
            nombre: nombre, capacidad: capacidad);
      } else {
        await repo.crearTipoHabitacion(nombre, capacidad: capacidad);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _guardando = false;
        _error = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar tipo' : 'Nuevo tipo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nombreCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre (ej: Estándar, Suite)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _capacidadCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Capacidad (máx. personas)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
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
