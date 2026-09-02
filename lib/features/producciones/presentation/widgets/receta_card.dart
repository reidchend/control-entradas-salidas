import 'package:flutter/material.dart';

import '../../../../core/models/receta.dart';

/// Card de receta con badges de tipo/componentes/cantidad (porta
/// `_build_card` de `recetas_view.py`).
class RecetaCard extends StatelessWidget {
  const RecetaCard({
    super.key,
    required this.receta,
    required this.totalComponentes,
    required this.ingredientes,
    required this.resultados,
    required this.variables,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Receta receta;
  final int totalComponentes;
  final int ingredientes;
  final int resultados;
  final int variables;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final esSimple = receta.tipo == 'simple';
    final tipoColor = esSimple ? Colors.green : scheme.tertiary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receta.nombre,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _badge(esSimple ? 'Simple' : 'Compuesta', tipoColor),
                        _badge('$totalComponentes comp.', scheme.onSurfaceVariant,
                            filled: true),
                        _badge(
                            'Cant: ${_fmtCant(receta.cantidadProducida)}',
                            scheme.onSurfaceVariant,
                            filled: true),
                        if (variables > 0)
                          _badge('$variables var.', Colors.orange,
                              filled: true, strong: true),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Editar',
                onPressed: onEdit,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
                tooltip: 'Eliminar',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color,
      {bool filled = false, bool strong = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.12) : color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: strong ? FontWeight.bold : FontWeight.normal,
          color: filled ? color : Colors.white,
        ),
      ),
    );
  }

  String _fmtCant(double c) {
    if (c == c.roundToDouble()) return c.toInt().toString();
    return c.toStringAsFixed(3);
  }
}
