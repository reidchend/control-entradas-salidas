import 'package:flutter/material.dart';

import '../../../../core/models/pos_cierre_models.dart';
import '../../../pos/data/reporte_cierre_texto.dart';

/// Tarjeta de un cierre en el historial: cajero a la vista, totales y botón
/// de reenvío del reporte por WhatsApp.
class CierreCard extends StatelessWidget {
  const CierreCard({
    super.key,
    required this.cierre,
    required this.onTap,
    required this.onReenviar,
  });

  final CierreCaja cierre;
  final VoidCallback onTap;
  final VoidCallback onReenviar;

  String get _cajero =>
      cierre.usuarioNombre.isNotEmpty ? cierre.usuarioNombre : 'Cajero sin nombre';

  String get _iniciales {
    final palabras =
        _cajero.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return palabras.take(2).map((p) => p[0].toUpperCase()).join();
  }

  String get _fechaCorta {
    final iso = cierre.cerradaEn;
    if (iso.length < 16) return iso;
    final fecha = iso.substring(0, 10);
    final hora = iso.substring(11, 16);
    return '${fecha.substring(8, 10)}/${fecha.substring(5, 7)} $hora';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          _iniciales,
          style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontSize: 13,
              fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(_cajero,
          style:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(
        'Turno #${cierre.sesionId} · $_fechaCorta · ${duracionCierreTexto(cierre)}',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FittedBox(
            child: Text(
              '\$${cierre.cajaFinal.toStringAsFixed(2)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                  fontSize: 16),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forward_to_inbox, size: 14, color: scheme.tertiary),
              const SizedBox(width: 4),
              Text('Reenviar',
                  style: TextStyle(fontSize: 11, color: scheme.tertiary)),
            ],
          ),
        ],
      ),
      onTap: onTap,
      onLongPress: onReenviar,
    );
  }
}
