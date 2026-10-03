import 'package:flutter/material.dart';

import '../../data/hostel_timeline_providers.dart';

/// Selector de vista de habitaciones: actual / semana / mes.
class HostelVistaSelector extends StatelessWidget {
  const HostelVistaSelector({
    super.key,
    required this.vista,
    required this.onChanged,
  });

  final HostelVista vista;
  final ValueChanged<HostelVista> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<HostelVista>(
      segments: const [
        ButtonSegment(
          value: HostelVista.actual,
          icon: Icon(Icons.grid_view),
          label: Text('Actual'),
        ),
        ButtonSegment(
          value: HostelVista.semana,
          icon: Icon(Icons.view_week_outlined),
          label: Text('Semana'),
        ),
        ButtonSegment(
          value: HostelVista.mes,
          icon: Icon(Icons.calendar_month_outlined),
          label: Text('Mes'),
        ),
      ],
      selected: {vista},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
