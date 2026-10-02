import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';

/// Panel inferior con las reservas/estancias activas y botón de nueva reserva.
class ReservasPanel extends StatelessWidget {
  const ReservasPanel({
    super.key,
    required this.reservas,
    required this.onReservar,
    required this.onRefresh,
  });

  final List<HostelReserva> reservas;
  final VoidCallback onReservar;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.event_note_outlined, size: 20),
              const SizedBox(width: 8),
              Text('Reservas activas (${reservas.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Refrescar',
                onPressed: onRefresh,
              ),
              FilledButton.icon(
                onPressed: onReservar,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Reservar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: reservas.isEmpty
                ? Center(
                    child: Text(
                      'No hay reservas activas',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView(
                    children: [
                      for (final r in reservas) _ReservaRow(reserva: r),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReservaRow extends StatelessWidget {
  const _ReservaRow({required this.reserva});

  final HostelReserva reserva;

  @override
  Widget build(BuildContext context) {
    final estado = switch (reserva.estado) {
      HostelReservaEstado.reservada => 'Reservada',
      HostelReservaEstado.ocupada => 'Ocupada',
      HostelReservaEstado.finalizada => 'Finalizada',
      HostelReservaEstado.cancelada => 'Cancelada',
    };
    String f(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return ListTile(
      dense: true,
      leading: Icon(
        reserva.estado == HostelReservaEstado.ocupada
            ? Icons.bed
            : Icons.event_available,
        color: reserva.estado == HostelReservaEstado.ocupada
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.tertiary,
      ),
      title: Text('${reserva.habitacionNumero ?? reserva.habitacionId} · '
          '${reserva.huespedNombre ?? ''}'),
      subtitle: Text('${f(reserva.fechaIngreso)} → ${f(reserva.fechaSalida)} · $estado'),
    );
  }
}