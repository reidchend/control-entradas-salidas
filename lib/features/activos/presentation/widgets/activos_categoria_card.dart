import 'package:flutter/material.dart';

import '../../data/activos_categoria.dart';

/// Card de categoría de activo (estilo `categoria_card` de Inventario).
class ActivosCategoriaCard extends StatelessWidget {
  const ActivosCategoriaCard({
    super.key,
    required this.categoria,
    required this.conteo,
    required this.onTap,
  });

  final ActivosCategoria categoria;
  final int conteo;
  final VoidCallback onTap;

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
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              Text(
                categoria.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}