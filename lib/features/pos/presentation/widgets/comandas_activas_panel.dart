import 'package:flutter/material.dart';

import '../../data/pos_comanda_models.dart';

/// Panel "Comandas activas" del home: listado de mesas/habitaciones con
/// comanda abierta para retomarlas de un toque. Solo se muestra si hay.
class ComandasActivasPanel extends StatelessWidget {
  const ComandasActivasPanel({
    super.key,
    required this.comandas,
    required this.onAbrirComanda,
    this.onMover,
    this.onFusionar,
  });

  final List<ComandaActiva> comandas;
  final void Function(int? mesaId, int? habitacionId) onAbrirComanda;

  /// Acciones opcionales de casilla por comanda (menú `⋮`).
  final void Function(ComandaActiva comanda)? onMover;
  final void Function(ComandaActiva comanda)? onFusionar;

  @override
  Widget build(BuildContext context) {
    if (comandas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.playlist_play, size: 20, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              'Comandas activas (${comandas.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF66BB6A).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF66BB6A).withValues(alpha: 0.3),
                ),
              ),
              child: const Text(
                'En curso',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF81C784),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: comandas.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _ComandaActivaTile(
              comanda: comandas[i],
              onTap: () =>
                  onAbrirComanda(comandas[i].mesaId, comandas[i].habitacionId),
              onMover: onMover == null ? null : () => onMover!(comandas[i]),
              onFusionar:
                  onFusionar == null ? null : () => onFusionar!(comandas[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ComandaActivaTile extends StatelessWidget {
  const _ComandaActivaTile({
    required this.comanda,
    required this.onTap,
    this.onMover,
    this.onFusionar,
  });

  final ComandaActiva comanda;
  final VoidCallback onTap;
  final VoidCallback? onMover;
  final VoidCallback? onFusionar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final esMesa = comanda.mesaId != null;
    final color = esMesa ? const Color(0xFFEF5350) : const Color(0xFF4FC3F7);
    final icono = esMesa ? Icons.restaurant : Icons.hotel;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.14),
                scheme.surfaceContainerHigh.withValues(alpha: 0.5),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.2),
                ),
                child: Icon(icono, size: 22, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comanda.etiqueta,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${comanda.items} item${comanda.items == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${comanda.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Abrir',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: color),
                    ],
                  ),
                ],
              ),
              if (onMover != null || onFusionar != null)
                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                  onSelected: (v) {
                    if (v == 'mover') onMover?.call();
                    if (v == 'fusionar') onFusionar?.call();
                  },
                  itemBuilder: (_) => [
                    if (onMover != null)
                      const PopupMenuItem(
                        value: 'mover',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.drive_file_move_outline),
                          title: Text('Mover a otra casilla'),
                        ),
                      ),
                    if (onFusionar != null)
                      const PopupMenuItem(
                        value: 'fusionar',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.merge_type),
                          title: Text('Fusionar con…'),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}