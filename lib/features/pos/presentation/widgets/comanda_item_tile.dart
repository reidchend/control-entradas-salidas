import 'package:flutter/material.dart';

import '../../data/pos_comanda_models.dart';

/// Renglón de un ítem de la comanda: nombre, precio, contornos, cantidad y
/// total. Si [mostrarCliente] es true, muestra la sub-cuenta ("Cliente N")
/// como badge tocable ([onCliente]) para reasignarla.
class ComandaItemTile extends StatelessWidget {
  const ComandaItemTile({
    super.key,
    required this.item,
    required this.index,
    required this.onMenos,
    required this.onMas,
    required this.onEliminar,
    this.onCliente,
    this.mostrarCliente = false,
  });

  final ComandaItem item;
  final int index;
  final VoidCallback onMenos;
  final VoidCallback onMas;
  final VoidCallback onEliminar;
  final VoidCallback? onCliente;
  final bool mostrarCliente;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: index.isEven
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombre,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Text(
                      '\$${item.precio.toStringAsFixed(2)}',
                      style:
                          TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                    if (mostrarCliente) _badge(),
                  ],
                ),
                for (final c in item.contornos)
                  Row(
                    children: [
                      const Icon(Icons.add, size: 10, color: Color(0xFFF57C00)),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          c.cantidad > 1
                              ? '${c.cantidad}x ${c.nombre}'
                              : c.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFFF57C00)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onMenos,
            icon: const Icon(Icons.remove_circle_outline,
                size: 18, color: Color(0xFFF57C00)),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Text(
              '${item.cantidad}',
              key: ValueKey(item.cantidad),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onMas,
            icon: const Icon(Icons.add_circle_outline,
                size: 18, color: Color(0xFF4CAF50)),
          ),
          const SizedBox(width: 4),
          Text(
            '\$${item.subtotal.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4CAF50)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onEliminar,
            icon: const Icon(Icons.delete_outline,
                size: 18, color: Color(0xFFEF5350)),
          ),
        ],
      ),
    );
  }

  Widget _badge() {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF7E3FF2).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF7E3FF2).withValues(alpha: 0.35)),
      ),
      child: Text(
        item.cuentaNombre ?? 'Cliente ${item.cuenta}',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: Color(0xFF7E3FF2),
        ),
      ),
    );
    final contenido = Padding(
      padding: const EdgeInsets.only(left: 6),
      child: badge,
    );
    if (onCliente == null) return contenido;
    return InkWell(
      onTap: onCliente,
      borderRadius: BorderRadius.circular(10),
      child: contenido,
    );
  }
}
