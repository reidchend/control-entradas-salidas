import 'package:flutter/material.dart';

import '../../../data/pos_turno_models.dart';
import '../../../data/reporte_cierre_texto.dart';

/// Card del turno abierto en la vista pública de Turnos (login).
class TurnoAbiertoCard extends StatelessWidget {
  const TurnoAbiertoCard({
    super.key,
    required this.turno,
    this.onUnirse,
  });

  final TurnoAbierto turno;
  final VoidCallback? onUnirse;

  String _hora(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final participantes = turno.participantes;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storefront, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Turno abierto',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '#${turno.id}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Abrió ${turno.aperturistaNombre} · ${_hora(turno.abiertaEn)}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '${participantes.where((p) => p.enTurno).length} usuarios en el turno'
              ' · ${turno.ventas} ventas · \$${fmtNumCierre(turno.totalVentas)}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (participantes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in participantes)
                    _ParticipanteChip(participante: p),
                ],
              ),
            ],
            if (onUnirse != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onUnirse,
                  icon: const Icon(Icons.login),
                  label: const Text('Unirse al turno'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParticipanteChip extends StatelessWidget {
  const _ParticipanteChip({required this.participante});

  final ParticipanteTurno participante;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activo = participante.enTurno;
    final enLinea = participante.enLinea;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: activo
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            participante.esAperturista ? Icons.star : Icons.person_outline,
            size: 14,
            color: activo ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            participante.nombre,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color:
                  activo ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
            ),
          ),
          if (enLinea) ...[
            const SizedBox(width: 5),
            Icon(Icons.circle, size: 7, color: scheme.primary),
          ],
        ],
      ),
    );
  }
}
