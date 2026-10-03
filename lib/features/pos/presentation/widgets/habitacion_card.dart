import 'package:flutter/material.dart';

import '../../../../core/models/pos_models.dart';
import 'estado_card.dart';

const _disponibleColor = Color(0xFF26A69A);
const _ocupadaColor = Color(0xFFEF5350);

/// Card de habitación (diseño mejorado sobre `HabitacionesView._build_card`):
/// número en círculo con glow, badge Ocupada/Disponible y piso/tipo.
class HabitacionCard extends StatelessWidget {
  const HabitacionCard({
    super.key,
    required this.habitacion,
    required this.ocupada,
    this.onTap,
  });

  final Habitacion habitacion;
  final bool ocupada;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final info = [habitacion.piso, habitacion.tipo]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' - ');

    return EstadoCard(
      numero: habitacion.numero,
      estado: ocupada ? 'Ocupada' : 'Disponible',
      info: info.isEmpty ? 'HAB ${habitacion.numero}' : info.toUpperCase(),
      color: ocupada ? _ocupadaColor : _disponibleColor,
      onTap: onTap,
    );
  }
}