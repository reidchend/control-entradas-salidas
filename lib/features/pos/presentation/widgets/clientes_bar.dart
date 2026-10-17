import 'package:flutter/material.dart';

/// Barra de sub-cuentas ("clientes") dentro de una comanda. Permite elegir a
/// qué cliente entran los productos nuevos y crear uno nuevo. Un `-`/`+` por
/// cliente sería redundante; el cliente activo define el destino de alta.
class ClientesBar extends StatelessWidget {
  const ClientesBar({
    super.key,
    required this.clientes,
    required this.activo,
    required this.onSelect,
    required this.onNuevo,
  });

  final List<int> clientes;
  final int activo;
  final ValueChanged<int> onSelect;
  final VoidCallback onNuevo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Icon(Icons.groups_outlined, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('Clientes',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in clientes) ...[
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('Cliente $c'),
                      selected: c == activo,
                      onSelected: (_) => onSelect(c),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            tooltip: 'Nuevo cliente',
            onPressed: onNuevo,
            icon: const Icon(Icons.person_add_alt, size: 16),
          ),
        ],
      ),
    );
  }
}
