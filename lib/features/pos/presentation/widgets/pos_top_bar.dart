import 'package:flutter/material.dart';

import '../../../../core/models/pos_models.dart';

/// Barra superior del POS (port de `MesasView._build_top_bar` / comandas.py):
/// logo + título a la izquierda; avatar, rol y cerrar sesión a la derecha. El
/// botón de config (solo admin) lo agrega la vista que lo necesite.
class PosTopBar extends StatelessWidget {
  const PosTopBar({
    super.key,
    required this.usuario,
    this.titulo = 'POS',
    this.onBack,
    this.onLogout,
    this.actions = const [],
    this.mostrarPerfil = true,
  });

  final PosUsuario usuario;
  final String titulo;
  final VoidCallback? onBack;
  final VoidCallback? onLogout;
  final List<Widget> actions;
  /// Oculta el avatar, nombre y rol del cajero (útil en pantallas pequeñas
  /// como la de comandas en tablets).
  final bool mostrarPerfil;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final esAdmin = usuario.esAdmin;
    final iniciales = usuario.nombre.isEmpty
        ? '?'
        : usuario.nombre.substring(0, 2).toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Volver',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          const SizedBox(width: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/icono_azul.png',
              width: 26,
              height: 26,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            titulo,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          ...actions,
          const SizedBox(width: 4),
          if (mostrarPerfil) ...[
            CircleAvatar(
              radius: 18,
              backgroundColor:
                  esAdmin ? const Color(0xFFF57C00) : scheme.primaryContainer,
              child: Text(
                iniciales,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: esAdmin ? Colors.white : scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  usuario.nombre,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text(
                  esAdmin ? 'Administrador' : 'Cajero #${usuario.id}',
                  style: TextStyle(
                    fontSize: 11,
                    color: esAdmin
                        ? const Color(0xFFF57C00)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (onLogout != null)
              IconButton(
                tooltip: 'Cerrar sesión',
                onPressed: onLogout,
                icon: const Icon(Icons.logout, color: Color(0xFFEF5350)),
              ),
          ],
        ],
      ),
    );
  }
}
