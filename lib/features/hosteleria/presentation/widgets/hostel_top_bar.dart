import 'package:flutter/material.dart';

/// Barra superior de Hostelería: título, operador y botón de sincronizar.
class HostelTopBar extends StatelessWidget {
  const HostelTopBar({
    super.key,
    required this.nombreOperador,
    required this.onSync,
    required this.onLogout,
  });

  final String nombreOperador;
  final VoidCallback onSync;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: c.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.hotel_outlined, size: 26, color: c.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lycoris Hosteleria',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: c.onSurface)),
                if (nombreOperador.isNotEmpty)
                  Text('Operador: $nombreOperador',
                      style: TextStyle(fontSize: 12, color: c.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar',
            onPressed: onSync,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}