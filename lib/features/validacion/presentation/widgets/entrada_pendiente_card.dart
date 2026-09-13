import 'package:flutter/material.dart';

import '../../data/validacion_repository.dart';

/// Card de una entrada pendiente (porta el tile de `validacion_view.py`):
/// la tarjeta completa es clickeable para seleccionar/deseleccionar,
/// con borde resaltado cuando está seleccionada + botón eliminar.
class EntradaPendienteCard extends StatelessWidget {
  const EntradaPendienteCard({
    super.key,
    required this.entrada,
    required this.selected,
    required this.onToggle,
    required this.onEliminar,
  });

  final EntradaPendiente entrada;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onEliminar;

  String get _fecha {
    final f = entrada.fecha;
    if (f == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(f.day)}/${p(f.month)}/${f.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: onToggle,
        title: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: selected ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entrada.nombre,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${entrada.cantidadTexto} · ${entrada.almacen}'),
            if (_fecha.isNotEmpty)
              Text('Entrada: $_fecha',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            if ((entrada.observaciones ?? '').isNotEmpty)
              Text(
                entrada.observaciones!,
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: scheme.error),
          tooltip: 'Eliminar entrada',
          onPressed: onEliminar,
        ),
      ),
    );
  }
}
