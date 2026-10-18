import 'package:flutter/material.dart';

/// Barra de sub-cuentas ("clientes") dentro de una comanda.
///
/// Muestra cada cliente con su nombre personalizado (o "Cliente N") y el
/// subtotal que lleva. Toque un chip para **filtrar** la lista y ver solo
/// esos productos (y que los nuevos entren ahí); el chip "Todos" muestra la
/// comanda completa. Toque el chip ya filtrado (o manténgalo presionado)
/// para renombrarlo. Los botones ✏️/🗑️ gestionan el cliente filtrado
/// (nunca el base).
class ClientesBar extends StatelessWidget {
  const ClientesBar({
    super.key,
    required this.clientes,
    required this.activo,
    required this.filtro,
    required this.subtotales,
    required this.nombres,
    required this.onSelect,
    required this.onVerTodos,
    required this.onNuevo,
    required this.onRenombrar,
    required this.onEliminar,
  });

  final List<int> clientes;
  final int activo;

  /// Cliente cuyos productos se están viendo; `null` = ver todos.
  final int? filtro;
  final Map<int, double> subtotales;
  final Map<int, String> nombres;

  /// Tocar un chip de cliente: filtra y lo hace activo.
  final ValueChanged<int> onSelect;

  /// Chip "Todos": quita el filtro (el cliente activo no cambia).
  final VoidCallback onVerTodos;
  final VoidCallback onNuevo;
  final ValueChanged<int> onRenombrar;
  final ValueChanged<int> onEliminar;

  String etiqueta(int c) => nombres[c] ?? 'Cliente $c';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gestionable = filtro != null && filtro != 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.groups_outlined,
                  size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Tooltip(
                message: clientes.length == 1
                    ? 'Cuentas separadas: toque + para abrir otra cuenta'
                    : 'Toque un cliente para ver solo sus productos; toque su '
                        'chip otra vez para renombrarlo. Toque "Todos" para '
                        'ver la comanda completa.',
                child: Text('Clientes',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(
                          Icons.filter_alt_off_outlined,
                          size: 14,
                          color: filtro == null
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                        label: const Text('Todos'),
                        selected: filtro == null,
                        onSelected: (_) => onVerTodos(),
                      ),
                      const SizedBox(width: 6),
                      for (final c in clientes) ...[
                        GestureDetector(
                          onLongPress: () {
                            if (c != 1) onRenombrar(c);
                          },
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(etiqueta(c)),
                                if ((subtotales[c] ?? 0) > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '\$${(subtotales[c] ?? 0).toStringAsFixed(2)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: scheme.primary),
                                  ),
                                ],
                              ],
                            ),
                            selected: c == filtro,
                            onSelected: (_) {
                              if (c == filtro) {
                                // Ya se ve este cliente: tocarlo de nuevo
                                // vuelve a "Todos" (o renombra si no es 1).
                                if (c == 1) {
                                  onVerTodos();
                                } else {
                                  onRenombrar(c);
                                }
                              } else {
                                onSelect(c);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (gestionable) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Renombrar "${etiqueta(filtro!)}"',
                  onPressed: () => onRenombrar(filtro!),
                  icon: const Icon(Icons.edit_outline, size: 16),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Eliminar "${etiqueta(filtro!)}"',
                  onPressed: () => onEliminar(filtro!),
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: scheme.error),
                ),
              ],
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                tooltip: clientes.length == 1
                    ? 'Nueva cuenta separada'
                    : 'Añadir otra cuenta',
                onPressed: onNuevo,
                icon: const Icon(Icons.person_add_alt, size: 16),
              ),
            ],
          ),
          // Destino de los productos nuevos cuando se ve la comanda
          // completa (con filtro activo el destino es el propio chip).
          if (filtro == null && clientes.length > 1)
            Padding(
              padding: const EdgeInsets.only(left: 21, top: 2),
              child: Text(
                'Nuevo producto → ${etiqueta(activo)}',
                style: TextStyle(
                    fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
