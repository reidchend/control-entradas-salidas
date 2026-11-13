import 'package:flutter/material.dart';

import '../../../data/pos_turno_models.dart';
import '../../../data/reporte_cierre_texto.dart';

/// Card de un turno cerrado en la vista pública de Turnos.
class TurnoCerradoCard extends StatelessWidget {
  const TurnoCerradoCard({
    super.key,
    required this.turno,
    this.onVer,
  });

  final TurnoCerradoResumen turno;
  final VoidCallback? onVer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = turno.sesion;
    final abierta = fmtFechaCierre(s.abiertaEn);
    final cerrada = fmtFechaCierre(s.cerradaEn);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onVer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.surfaceContainerHighest,
                child: Icon(Icons.receipt_long_outlined,
                    color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Turno #${s.id} · ${turno.usuarioNombre ?? '—'}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$abierta → $cerrada',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${turno.ventas} ventas · '
                      '\$${fmtNumCierre(turno.totalVentas)}'
                      '${s.cajaFinal != null ? ' · caja \$${fmtNumCierre(s.cajaFinal!)}' : ''}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
