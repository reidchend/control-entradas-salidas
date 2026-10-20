import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/grupo_activos.dart';

/// Chips informativos de un grupo: estado, valor unitario/total, fecha y placas.
class GrupoActivosChips extends StatelessWidget {
  const GrupoActivosChips({super.key, required this.grupo});

  final GrupoActivos grupo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final a = grupo.plantilla;
    final rango = grupo.rangoCodigos;
    final estadoColor =
        grupo.activo ? colors.primary : appColor(context, 'warning');

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _chip(a.estado, estadoColor),
        if (a.valor > 0) _chip('Bs ${_fmt(a.valor)} c/u', colors.secondary),
        if (a.valor > 0 && grupo.cantidad > 1)
          _chip(
            'Total Bs ${_fmt(a.valor * grupo.cantidad)}',
            colors.secondary,
          ),
        if ((a.fecha ?? '').trim().isNotEmpty)
          _chip(a.fecha!.trim(), colors.onSurfaceVariant),
        if (rango.isNotEmpty) _chip(rango, colors.tertiary),
      ],
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}
