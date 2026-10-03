import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../../../../core/models/pos_models.dart';
import '../../data/hosteleria_repository.dart';
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
    final enAseo = hab.enAseo;
    final enMantenimiento = hab.enMantenimiento;
    final bloqueada = enAseo || enMantenimiento;
    return AlertDialog(
      title: Text('Habitación ${hab.numero}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([
            hab.piso,
            hab.tipo,
            'cap. ${hab.maxPersonas}',
          ].whereType<String>().join(' · ')),
          const SizedBox(height: 12),
          if (r != null)
            _reservaInfo(r)
          else
            _estadoInfo(hab),
          if (_cargando) const LinearProgressIndicator(),
        ],
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
              icon: const Icon(Icons.close),
              label: const Text('Cancelar reserva'),
              onPressed: _cargando
                  ? null
                  : () => _ejecutar(() => widget.repo.cancelarReserva(r.id)),
            ),
        ],
      ],
    );
  }

  Widget _estadoInfo(Habitacion hab) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, icon) = switch (hab.estado) {
      EstadoHabitacion.aseo => (
          'Aseo (pendiente de limpieza)',
          Colors.orange,
          Icons.cleaning_services_outlined,
        ),
      EstadoHabitacion.mantenimiento => (
          'En mantenimiento (no vendible)',
          scheme.error,
          Icons.build_outlined,
        ),
      _ => ('Disponible', Colors.green, Icons.check_circle_outline),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
        if ((hab.estadoNotas ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Nota: ${hab.estadoNotas}'),
          ),
      ],
    );
  }

  Widget _reservaInfo(HostelReserva r) {
    final scheme = Theme.of(context).colorScheme;
    final estado = switch (r.estado) {
      HostelReservaEstado.reservada => 'Reservada',
      HostelReservaEstado.ocupada => 'Ocupada',
      HostelReservaEstado.finalizada => 'Finalizada',
      HostelReservaEstado.cancelada => 'Cancelada',
    };
    String f(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    String h(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final restantes = r.minutosRestantes();
    final vencida = restantes != null && restantes < 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Huésped: ${r.huespedNombre ?? ''}'),
        Text('Modalidad: ${r.modalidadLabel}'),
        if (r.esPorHoras)
          Text('Entrada: ${f(r.fechaIngreso)}')
        else
          Text('Entrada: ${f(r.fechaIngreso)} · Salida: ${f(r.fechaSalida)}'),
        Text('Estado: $estado'),
        if (r.horaEntrada != null) Text('Hora de entrada: ${h(r.horaEntrada!)}'),
        if (r.horaSalida != null) Text('Hora de salida: ${h(r.horaSalida!)}'),
        if (r.horaLimite != null)
          Text(
            vencida
                ? 'Límite ${h(r.horaLimite!)} · VENCIDA (${-restantes} min)'
                : 'Límite ${h(r.horaLimite!)} · $restantes min restantes',
            style: TextStyle(
              color: vencida ? scheme.error : Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}
