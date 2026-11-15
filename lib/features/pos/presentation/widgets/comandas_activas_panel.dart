import 'package:flutter/material.dart';

import '../../data/pos_comanda_models.dart';

/// Color de una comanda que todavía no se imprimió para cocina (prioridad).
const _kPendiente = Color(0xFFFFB300);

/// Color de una comanda ya impresa para cocina.
const _kEnCocina = Color(0xFF66BB6A);

/// Panel "Comandas activas" del home: listado de mesas/habitaciones con
/// comanda abierta para retomarlas de un toque. Solo se muestra si hay.
///
/// Ayuda visual de cocina: las comandas que todavía **no** se imprimieron para
/// cocina (las que otro usuario acaba de cargar) se listan primero y se
/// resaltan en ámbar con el chip "Por imprimir"; al imprimir la comanda para
/// cocina pasan a verde con el chip "En cocina" (marca persistida en
/// `pos_comandas.impresa_en`).
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

    // Prioridad visual: las comandas sin imprimir se cuentan y se avisan en
    // el encabezado; además se listan primero (ver getComandasActivas).
    final nuevas = comandas.where((c) => c.impresaEn == null).length;
    final headerColor = nuevas > 0 ? _kPendiente : _kEnCocina;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.playlist_play, size: 20, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Comandas activas (${comandas.length})',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: headerColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: headerColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    nuevas > 0
                        ? Icons.priority_high_rounded
                        : Icons.soup_kitchen_outlined,
                    size: 13,
                    color: headerColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    nuevas > 0
                        ? '$nuevas por imprimir'
                        : 'En cocina',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: headerColor,
                    ),
                  ),
                ],
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
    // Sin imprimir = comanda nueva (prioridad visual); impresa = ya está en
    // cocina, así que se atenúa el resaltado.
    final pendiente = comanda.impresaEn == null;
    final acento = pendiente ? _kPendiente : color;

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
                acento.withValues(alpha: pendiente ? 0.20 : 0.14),
                scheme.surfaceContainerHigh.withValues(alpha: 0.5),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: acento.withValues(alpha: pendiente ? 0.75 : 0.25),
              width: pendiente ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: acento.withValues(alpha: 0.2),
                ),
                child: Icon(icono, size: 22, color: acento),
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
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${comanda.items} item${comanda.items == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        _EstadoCocinaChip(pendiente: pendiente),
                      ],
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

/// Chip de estado de cocina de una comanda activa: ámbar "Por imprimir"
/// mientras no se imprimió, verde "En cocina" una vez impresa.
class _EstadoCocinaChip extends StatelessWidget {
  const _EstadoCocinaChip({required this.pendiente});

  final bool pendiente;

  @override
  Widget build(BuildContext context) {
    final color = pendiente ? _kPendiente : _kEnCocina;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pendiente ? Icons.print_outlined : Icons.soup_kitchen_outlined,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            pendiente ? 'Por imprimir' : 'En cocina',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}