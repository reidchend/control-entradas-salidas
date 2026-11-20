import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../../data/hosteleria_repository.dart';
import '../widgets/habitacion_detalle_cards.dart';
import 'checkin_reserva_dialog.dart';

/// Detalle/acciones de una habitación: reservar, check-in (directo o desde
/// reserva), check-out, cancelar y estados de aseo/mantenimiento.
class HabitacionDetalleDialog extends StatefulWidget {
  const HabitacionDetalleDialog({
    super.key,
    required this.habitacion,
    required this.repo,
    required this.habitaciones,
    this.reserva,
  });

  final Habitacion habitacion;
  final HosteleriaRepository repo;
  final List<Habitacion> habitaciones;
  final HostelReserva? reserva;

  @override
  State<HabitacionDetalleDialog> createState() => _HabitacionDetalleDialogState();
}

class _HabitacionDetalleDialogState extends State<HabitacionDetalleDialog> {
  bool _cargando = false;

  Future<void> _abrir(CheckinModo modo) async {
    setState(() => _cargando = true);
    final ok = await showCheckinReservaDialog(
      context,
      repo: widget.repo,
      habitaciones: widget.habitaciones,
      modo: modo,
      habitacionFija: widget.habitacion,
      reservaExistente: widget.reserva,
    );
    if (!mounted) return;
    setState(() => _cargando = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() => _cargando = true);
    await accion();
    if (!mounted) return;
    setState(() => _cargando = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final hab = widget.habitacion;
    final r = widget.reserva;
    final scheme = Theme.of(context).colorScheme;
    final enAseo = hab.enAseo;
    final enMantenimiento = hab.enMantenimiento;
    final bloqueada = enAseo || enMantenimiento;
    return AlertDialog(
      title: const Text('Detalle de habitación'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r != null)
                ReservaDetalleCard(habitacion: hab, reserva: r)
              else
                EstadoDetalleCard(habitacion: hab),
              if (_cargando) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cerrar'),
        ),
        if (bloqueada)
          FilledButton.icon(
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Marcar limpia'),
            onPressed: _cargando
                ? null
                : () => _ejecutar(() => widget.repo.marcarLimpia(hab.id)),
          )
        else if (r == null) ...[
          OutlinedButton.icon(
            icon: const Icon(Icons.event_available),
            label: const Text('Reservar'),
            onPressed: _cargando ? null : () => _abrir(CheckinModo.reserva),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.login),
            label: const Text('Check-in directo'),
            onPressed:
                _cargando ? null : () => _abrir(CheckinModo.checkinDirecto),
          ),
          TextButton.icon(
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            label: const Text('Aseo'),
            onPressed: _cargando
                ? null
                : () => _ejecutar(() => widget.repo.enviarAAseo(hab.id)),
          ),
          TextButton.icon(
            icon: const Icon(Icons.build_outlined, size: 18),
            label: const Text('Mantenimiento'),
            onPressed: _cargando
                ? null
                : () => _ejecutar(() => widget.repo.ponerEnMantenimiento(hab.id)),
          ),
        ] else ...[
          if (r.estado == HostelReservaEstado.reservada)
            FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Check-in'),
              onPressed: _cargando
                  ? null
                  : () => _abrir(CheckinModo.checkinDesdeReserva),
            )
          else if (r.estado == HostelReservaEstado.ocupada)
            FilledButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Check-out'),
              onPressed: _cargando
                  ? null
                  : () => _ejecutar(() =>
                      widget.repo.realizarCheckOut(r.id, habitacionId: hab.id)),
            ),
          if (r.estado == HostelReservaEstado.reservada)
            TextButton.icon(
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancelar reserva'),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: _cargando
                  ? null
                  : () => _ejecutar(() => widget.repo.cancelarReserva(r.id)),
            ),
        ],
      ],
    );
  }
}
