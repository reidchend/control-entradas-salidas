import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../../../../core/models/pos_models.dart';
import '../../data/hosteleria_repository.dart';

/// Diálogo de nueva reserva: selecciona huésped (o crea uno) + fechas.
/// Retorna `true` si se creó la reserva.
Future<bool> showNuevaReservaDialog(
  BuildContext context, {
  required HosteleriaRepository repo,
  required List<PosHabitacion> habitaciones,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _NuevaReservaDialog(repo: repo, habitaciones: habitaciones),
  );
  return ok ?? false;
}

class _NuevaReservaDialog extends StatefulWidget {
  const _NuevaReservaDialog({
    required this.repo,
    required this.habitaciones,
  });

  final HosteleriaRepository repo;
  final List<PosHabitacion> habitaciones;

  @override
  State<_NuevaReservaDialog> createState() => _NuevaReservaDialogState();
}

class _NuevaReservaDialogState extends State<_NuevaReservaDialog> {
  PosHabitacion? _habitacion;
  HostelHuesped? _huesped;

  final _nombreCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  DateTime _ingreso = DateTime.now();
  DateTime _salida = DateTime.now().add(const Duration(days: 1));
  bool _cargando = false;
  String _error = '';

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _cedulaCtrl.dispose();
    _telCtrl.dispose();
    _correoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva reserva'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<PosHabitacion>(
                initialValue: _habitacion,
                decoration: const InputDecoration(labelText: 'Habitación'),
                items: [
                  for (final h in widget.habitaciones)
                    DropdownMenuItem(
                      value: h,
                      child: Text(
                          '${h.numero}${h.piso != null ? ' · ${h.piso}' : ''}'),
                    ),
                ],
                onChanged: (v) => setState(() => _habitacion = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre del huésped'),
                onChanged: (_) => setState(() {
                  _huesped = null;
                  _nombreCtrl.text = _nombreCtrl.text;
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cedulaCtrl,
                decoration: const InputDecoration(labelText: 'Cédula (opcional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _telCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _correoCtrl,
                decoration: const InputDecoration(labelText: 'Correo (opcional)'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.login),
                      label: Text(_fmt(_ingreso)),
                      onPressed: _cargando
                          ? null
                          : () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _ingreso,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 366)),
                              );
                              if (d != null) {
                                setState(() {
                                  _ingreso = d;
                                  if (_salida.isBefore(d)) {
                                    _salida = d.add(const Duration(days: 1));
                                  }
                                });
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout),
                      label: Text(_fmt(_salida)),
                      onPressed: _cargando
                          ? null
                          : () async {
                              final inicioMin = _ingreso.add(const Duration(days: 1));
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _salida.isAfter(inicioMin)
                                    ? _salida
                                    : inicioMin,
                                firstDate: inicioMin,
                                lastDate: DateTime.now().add(const Duration(days: 366)),
                              );
                              if (d != null) setState(() => _salida = d);
                            },
                    ),
                  ),
                ],
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cargando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: _cargando
              ? const SizedBox(
                  height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: const Text('Reservar'),
          onPressed: _cargando ? null : _guardar,
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    if (_habitacion == null) {
      setState(() => _error = 'Selecciona una habitación');
      return;
    }
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Ingresa el nombre del huésped');
      return;
    }
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      var huesped = _huesped;
      huesped ??= await widget.repo.saveHuesped(
        nombre: nombre,
        cedula: _cedulaCtrl.text,
        telefono: _telCtrl.text,
        correo: _correoCtrl.text,
      );
      await widget.repo.crearReserva(
        habitacionId: _habitacion!.id,
        huesped: huesped,
        fechaIngreso: _ingreso,
        fechaSalida: _salida,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = 'Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}