import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../../../../core/models/pos_models.dart';
import '../../data/hosteleria_repository.dart';
import 'nueva_reserva_dialog.dart';

/// Detalle/acciones de una habitación: reservar, check-in, check-out,
/// cancelar. Un diálogo = una responsabilidad.
class HabitacionDetalleDialog extends StatefulWidget {
  const HabitacionDetalleDialog({
    super.key,
    required this.habitacion,
    required this.repo,
    this.reserva,
  });

  final PosHabitacion habitacion;
  final HosteleriaRepository repo;
  final HostelReserva? reserva;

  @override
  State<HabitacionDetalleDialog> createState() => _HabitacionDetalleDialogState();
}

class _HabitacionDetalleDialogState extends State<HabitacionDetalleDialog> {
  bool _cargando = false;

  @override
  Widget build(BuildContext context) {
    final hab = widget.habitacion;
    final r = widget.reserva;
    return AlertDialog(
      title: Text('Habitación ${hab.numero}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([hab.piso, hab.tipo].whereType<String>().join(' · ')),
          const SizedBox(height: 12),
          if (r == null)
            const Text('Disponible', style: TextStyle(color: Colors.green))
          else
            _reservaInfo(r),
          if (_cargando) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cerrar'),
        ),
        if (r == null)
          FilledButton.icon(
            icon: const Icon(Icons.event_available),
            label: const Text('Reservar'),
            onPressed: _cargando
                ? null
                : () async {
                    setState(() => _cargando = true);
                    final ok = await showNuevaReservaDialog(
                      context,
                      repo: widget.repo,
                      habitaciones: [hab],
                    );
                    setState(() => _cargando = false);
                    if (ok && context.mounted) Navigator.pop(context, true);
                  },
          )
        else ...[
          if (r.estado == HostelReservaEstado.reservada)
            FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Check-in'),
              onPressed: _cargando
                  ? null
                  : () async {
                      setState(() => _cargando = true);
                      await widget.repo.realizarCheckIn(r.id);
                      setState(() => _cargando = false);
                      if (context.mounted) Navigator.pop(context, true);
                    },
            )
          else if (r.estado == HostelReservaEstado.ocupada)
            FilledButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Check-out'),
              onPressed: _cargando
                  ? null
                  : () async {
                      setState(() => _cargando = true);
                      await widget.repo.realizarCheckOut(r.id);
                      setState(() => _cargando = false);
                      if (context.mounted) Navigator.pop(context, true);
                    },
            ),
          TextButton.icon(
            icon: const Icon(Icons.close),
            label: const Text('Cancelar reserva'),
            onPressed: _cargando
                ? null
                : () async {
                    setState(() => _cargando = true);
                    await widget.repo.cancelarReserva(r.id);
                    setState(() => _cargando = false);
                    if (context.mounted) Navigator.pop(context, true);
                  },
          ),
        ],
      ],
    );
  }

  Widget _reservaInfo(HostelReserva r) {
    final estado = switch (r.estado) {
      HostelReservaEstado.reservada => 'Reservada',
      HostelReservaEstado.ocupada => 'Ocupada',
      HostelReservaEstado.finalizada => 'Finalizada',
      HostelReservaEstado.cancelada => 'Cancelada',
    };
    String f(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Huésped: ${r.huespedNombre ?? ''}'),
        Text('Entrada: ${f(r.fechaIngreso)} · Salida: ${f(r.fechaSalida)}'),
        Text('Estado: $estado'),
      ],
    );
  }
}