import 'package:flutter/material.dart';

import '../../data/activos_categoria.dart';

/// Card de categoría de activo (estilo `categoria_card` de Inventario).
class ActivosCategoriaCard extends StatelessWidget {
  const ActivosCategoriaCard({
    super.key,
    required this.categoria,
    required this.conteo,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final ActivosCategoria categoria;
  final int conteo;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorHex = categoria.color.replaceFirst('#', '0xFF');
    final color = int.tryParse(colorHex) ?? 0xFF2196F3;

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(color), Color(color).withValues(alpha: .75)],
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      color: Colors.white, size: 22),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$conteo',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      categoria.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (onEdit != null || onDelete != null)
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      color: Colors.white,
                      icon: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.more_vert, color: Colors.white),
                      ),
                      onSelected: (v) {
                        if (v == 'editar') onEdit?.call();
                        if (v == 'eliminar') onDelete?.call();
                      },
                      itemBuilder: (_) => [
                        if (onEdit != null)
                          const PopupMenuItem(
                              value: 'editar', child: Text('Editar')),
                        if (onDelete != null)
                          const PopupMenuItem(
                              value: 'eliminar', child: Text('Eliminar')),
                      ],
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
