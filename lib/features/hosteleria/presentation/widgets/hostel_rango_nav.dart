import 'package:flutter/material.dart';

import '../../../../core/utils/fecha_utils.dart';
import '../../data/hostel_timeline_providers.dart';

/// Navegación de rango (semana/mes): anterior, título y siguiente.
class HostelRangoNav extends StatelessWidget {
  const HostelRangoNav({
    super.key,
    required this.vista,
    required this.ancla,
    required this.onMover,
  });

  final HostelVista vista;
  final DateTime ancla;
  final ValueChanged<DateTime> onMover;

  String get _titulo {
    if (vista == HostelVista.mes) return '${mesLargo(ancla)} ${ancla.year}';
    final r = rangoDe(vista, ancla);
    return '${fmtFecha(r.desde)} – ${fmtFecha(r.hasta)}';
  }

  void _paso(int dir) {
    if (vista == HostelVista.mes) {
      onMover(sumarMeses(ancla, dir));
    } else {
      onMover(ancla.add(Duration(days: 7 * dir)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Anterior',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _paso(-1),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 190),
          child: Text(
            _titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Siguiente',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _paso(1),
        ),
        TextButton(
          onPressed: () => onMover(soloFecha(DateTime.now())),
          child: const Text('Hoy'),
        ),
      ],
    );
  }
}
