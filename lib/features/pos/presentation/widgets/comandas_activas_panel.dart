import 'package:flutter/material.dart';

import '../../data/pos_comanda_models.dart';

/// Color de una comanda que todavía no se imprimió para cocina (prioridad).
const _kPendiente = Color(0xFFFFB300);

/// Color de una comanda ya impresa para cocina y sin cambios después.
const _kEnCocina = Color(0xFF66BB6A);

/// Panel "Comandas activas" del home: listado de mesas/habitaciones con
/// comanda abierta para retomarlas de un toque. Solo se muestra si hay.
///
/// Ayuda visual de cocina con tres estados:
///
/// - **Por imprimir** (ámbar): nunca se imprimió para cocina. Es la que otro
///   usuario acaba de cargar y tiene prioridad visual.
/// - **Modificada** (ámbar): ya se imprimió pero se editó después (agregó/
///   quitó productos o cambió el total), así que hay que reimprimirla.
/// - **En cocina** (verde): ya se imprimió y no se tocó después.
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

    // Estados de cocina calculados por comanda (el orden de la lista ya los
    // deja agrupados: por imprimir, modificadas, en cocina).
    final porImprimir = comandas.where(_esPorImprimir).length;
    final modificadas = comandas.where(_esModificada).length;
    final pendientes = porImprimir + modificadas;
    final headerColor = pendientes > 0 ? _kPendiente : _kEnCocina;

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
                    pendientes > 0
                        ? Icons.priority_high_rounded
                        : Icons.soup_kitchen_outlined,
                    size: 13,
                    color: headerColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    pendientes > 0
                        ? _textoResumen(porImprimir, modificadas)
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

  String _textoResumen(int porImprimir, int modificadas) {
    final partes = <String>[];
    if (porImprimir > 0) partes.add('$porImprimir por imprimir');
    if (modificadas > 0) partes.add('$modificadas modificada${modificadas == 1 ? '' : 's'}');
    return partes.join(' · ');
  }

  static bool _esPorImprimir(ComandaActiva c) => c.impresaEn == null;

  static bool _esModificada(ComandaActiva c) {
    if (c.impresaEn == null || c.updatedAt == null) return false;
    return c.updatedAt!.isAfter(c.impresaEn!);
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

  /// Estado de cocina de esta comanda.
  _EstadoCocina get _estado {
    if (comanda.impresaEn == null) return _EstadoCocina.porImprimir;
    if (_esModificada) return _EstadoCocina.modificada;
    return _EstadoCocina.enCocina;
  }

  bool get _esModificada {
    if (comanda.impresaEn == null || comanda.updatedAt == null) return false;
    return comanda.updatedAt!.isAfter(comanda.impresaEn!);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final esMesa = comanda.mesaId != null;
    final colorBase = esMesa ? const Color(0xFFEF5350) : const Color(0xFF4FC3F7);
    final icono = esMesa ? Icons.restaurant : Icons.hotel;

    // Sin imprimir o modificada = necesita atención visual (ámbar). Impresa
    // y sin cambios = se atenúa el resaltado (color de la casilla).
    final necesitaAtencion = _estado == _EstadoCocina.porImprimir ||
        _estado == _EstadoCocina.modificada;
    final acento = _estado == _EstadoCocina.enCocina ? colorBase : _kPendiente;

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
                acento.withValues(alpha: necesitaAtencion ? 0.20 : 0.14),
                scheme.surfaceContainerHigh.withValues(alpha: 0.5),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: acento.withValues(alpha: necesitaAtencion ? 0.75 : 0.25),
              width: necesitaAtencion ? 1.6 : 1,
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
                        _EstadoCocinaChip(estado: _estado),
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
                          color: colorBase,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: colorBase),
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

/// Estado de cocina de una comanda activa.
enum _EstadoCocina {
  /// Nunca se imprimió para cocina.
  porImprimir,
  /// Ya se imprimió pero se editó después: hay que reimprimir.
  modificada,
  /// Ya se imprimió y no se tocó después.
  enCocina,
}

/// Chip de estado de cocina de una comanda activa.
class _EstadoCocinaChip extends StatelessWidget {
  const _EstadoCocinaChip({required this.estado});

  final _EstadoCocina estado;

  @override
  Widget build(BuildContext context) {
    final color = estado == _EstadoCocina.enCocina ? _kEnCocina : _kPendiente;
    final (IconData icono, String texto) = switch (estado) {
      _EstadoCocina.porImprimir => (Icons.print_outlined, 'Por imprimir'),
      _EstadoCocina.modificada => (Icons.edit_outlined, 'Modificada'),
      _EstadoCocina.enCocina => (Icons.soup_kitchen_outlined, 'En cocina'),
    };
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
          Icon(icono, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            texto,
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
