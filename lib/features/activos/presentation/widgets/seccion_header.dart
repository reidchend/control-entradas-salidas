import 'package:flutter/material.dart';

/// Encabezado de sección reutilizable (categoría, grupo, ubicación...).
class SeccionHeader extends StatelessWidget {
  const SeccionHeader({
    super.key,
    required this.titulo,
    required this.icono,
    this.color,
    this.conteo,
    this.pequeno = false,
  });

  final String titulo;
  final IconData icono;
  final Color? color;
  final int? conteo;
  final bool pequeno;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final c = color ?? colors.primary;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, pequeno ? 10 : 14, 12, 4),
      child: Row(
        children: [
          Icon(icono, size: pequeno ? 16 : 18, color: c),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: pequeno ? 13 : 15,
                color: c,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conteo != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$conteo',
                style: TextStyle(
                    fontSize: 11, color: c, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}