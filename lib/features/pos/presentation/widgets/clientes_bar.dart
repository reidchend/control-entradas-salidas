import 'package:flutter/material.dart';

/// Barra de sub-cuentas ("clientes") dentro de una comanda.
///
/// Muestra cada cliente con su nombre personalizado (o "Cliente N") y el
/// subtotal que lleva, para que el mesonero vea de un vistazo cómo se reparte
/// la mesa. El chip activo define a dónde entran los productos nuevos.
///
/// Acciones: tocar un chip lo activa; tocar el chip ya activo (o mantenerlo
/// presionado) abre su gestión. Los botones ✏️/🗑️ actúan sobre el cliente
/// activo (solo para clientes distintos del base).
class ClientesBar extends StatelessWidget {
  const ClientesBar({
    super.key,
    required this.clientes,
    required this.activo,
    required this.subtotales,
    required this.nombres,
    required this.onSelect,
    required this.onNuevo,
    required this.onRenombrar,
    required this.onEliminar,
  });

  final List<int> clientes;
  final int activo;
  final Map<int, double> subtotales;
  final Map<int, String> nombres;
  final ValueChanged<int> onSelect;
  final VoidCallback onNuevo;
  final ValueChanged<int> onRenombrar;
  final ValueChanged<int> onEliminar;

  String etiqueta(int c) => nombres[c] ?? 'Cliente $c';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final puedeGestionar = activo != 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Icon(Icons.groups_outlined, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Tooltip(
            message: clientes.length == 1
                ? 'Cuentas separadas: toque + para abrir otra cuenta'
                : 'Toque un cliente para elegir dónde entran los productos. '
                    'Toque el cliente activo para ponerle nombre o eliminarlo.',
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
                        selected: c == activo,
                        onSelected: (_) {
                          if (c == activo) {
                            if (puedeGestionar) onRenombrar(c);
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
          if (puedeGestionar) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Renombrar "${etiqueta(activo)}"',
              onPressed: () => onRenombrar(activo),
              icon: const Icon(Icons.edit_outline, size: 16),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Eliminar "${etiqueta(activo)}"',
              onPressed: () => onEliminar(activo),
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
    );
  }
}
