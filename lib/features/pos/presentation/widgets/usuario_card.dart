import 'package:flutter/material.dart';

import '../../../../core/models/pos_models.dart';

/// Card de cajero (login.py `_build_usuario_card`): avatar con iniciales,
/// nombre, badges (Admin / Con PIN / Sin PIN) y estado de la tarjeta.
class UsuarioCard extends StatelessWidget {
  const UsuarioCard({
    super.key,
    required this.usuario,
    this.selected = false,
    this.turnoAbierto = false,
    this.onTap,
  });

  final PosUsuario usuario;
  final bool selected;
  final bool turnoAbierto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final esAdmin = usuario.esAdmin;
    final hasPin = usuario.pinHash != null && usuario.pinHash!.isNotEmpty;

    final badges = <String>[
      if (esAdmin) 'Admin',
      if (usuario.esDesarrollador) 'Desarrollador',
      hasPin ? 'Con PIN' : 'Sin PIN',
    ];

    return Card(
      elevation: selected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: esAdmin
                    ? const Color(0xFFF57C00)
                    : scheme.primaryContainer,
                child: Text(
                  usuario.nombre.isEmpty
                      ? '?'
                      : usuario.nombre.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: esAdmin
                        ? Colors.white
                        : scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      usuario.nombre,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      badges.join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (turnoAbierto) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront,
                          size: 14, color: scheme.onSecondaryContainer),
                      const SizedBox(width: 4),
                      Text(
                        'En turno',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                esAdmin
                    ? Icons.admin_panel_settings_outlined
                    : hasPin
                        ? Icons.lock_outline
                        : Icons.lock_open_outlined,
                size: 20,
                color: esAdmin
                    ? const Color(0xFFF57C00)
                    : scheme.onSurfaceVariant,
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle, color: scheme.primary, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
