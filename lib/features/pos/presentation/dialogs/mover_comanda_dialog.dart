import 'package:flutter/material.dart';

import '../../../../core/models/pos_models.dart';

/// Casilla destino elegida (mesa o habitación) con su etiqueta legible.
typedef DestinoCasilla = ({int? mesaId, int? habitacionId, String etiqueta});

/// Diálogo para elegir la casilla destino de una comanda (mover o separar).
/// [mesas] y [habitaciones] deben venir ya filtradas a las libres.
Future<DestinoCasilla?> showMoverComandaDialog(
  BuildContext context, {
  required List<PosMesa> mesas,
  required List<Habitacion> habitaciones,
  String titulo = 'Mover comanda',
  String? subtitulo,
}) {
  return showDialog<DestinoCasilla>(
    context: context,
    builder: (ctx) => _MoverComandaDialog(
      mesas: mesas,
      habitaciones: habitaciones,
      titulo: titulo,
      subtitulo: subtitulo,
    ),
  );
}

String etiquetaMesa(PosMesa m) {
  final extra = [m.nombre, m.zona]
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .join(' · ');
  return 'Mesa ${m.numero}${extra.isNotEmpty ? ' · $extra' : ''}';
}

String etiquetaHabitacion(Habitacion h) {
  final extra = [h.tipo, h.piso == null ? null : 'Piso ${h.piso}']
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .join(' · ');
  return 'Hab ${h.numero}${extra.isNotEmpty ? ' · $extra' : ''}';
}

class _MoverComandaDialog extends StatelessWidget {
  const _MoverComandaDialog({
    required this.mesas,
    required this.habitaciones,
    required this.titulo,
    this.subtitulo,
  });

  final List<PosMesa> mesas;
  final List<Habitacion> habitaciones;
  final String titulo;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vacio = mesas.isEmpty && habitaciones.isEmpty;
    return AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subtitulo != null) ...[
                Text(subtitulo!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
              ],
              if (vacio)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No hay mesas ni habitaciones libres.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              if (mesas.isNotEmpty) ...[
                _seccion(context, Icons.restaurant, 'Mesas', const Color(0xFFEF5350)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in mesas)
                      _chip(
                        context,
                        etiquetaMesa(m),
                        const Color(0xFFEF5350),
                        () => Navigator.pop(context, (
                          mesaId: m.id,
                          habitacionId: null,
                          etiqueta: etiquetaMesa(m),
                        )),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (habitaciones.isNotEmpty) ...[
                _seccion(context, Icons.hotel, 'Habitaciones', const Color(0xFF4FC3F7)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final h in habitaciones)
                      _chip(
                        context,
                        etiquetaHabitacion(h),
                        const Color(0xFF4FC3F7),
                        () => Navigator.pop(context, (
                          mesaId: null,
                          habitacionId: h.id,
                          etiqueta: etiquetaHabitacion(h),
                        )),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _seccion(BuildContext context, IconData icono, String texto, Color color) {
    return Row(
      children: [
        Icon(icono, size: 16, color: color),
        const SizedBox(width: 6),
        Text(texto, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, Color color, VoidCallback onTap) {
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(Icons.meeting_room_outlined, size: 16, color: color),
      label: Text(label),
    );
  }
}
