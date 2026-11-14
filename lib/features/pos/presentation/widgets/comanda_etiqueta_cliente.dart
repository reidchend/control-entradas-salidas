import 'package:flutter/material.dart';

/// Etiqueta compacta del cliente de la comanda: `Particular` o las
/// habitaciones seleccionadas (`Hab 101 · Hab 103`).
///
/// Vive en la barra superior para no repetir la ubicación (la mesa ya está en
/// el título) y no gastar una franja extra de altura en tablets.
class ComandaEtiquetaCliente extends StatelessWidget {
  const ComandaEtiquetaCliente({super.key, required this.habitaciones});

  /// `null`/vacío = sin etiqueta; `'Particular'`; o `'101, 103'`.
  final String? habitaciones;

  bool get _esParticular => habitaciones == 'Particular';

  List<String> get _lista {
    final txt = habitaciones;
    if (txt == null || txt.isEmpty || _esParticular) return const [];
    return txt
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final txt = habitaciones;
    if (txt == null || txt.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final fondo =
        _esParticular ? scheme.secondaryContainer : scheme.primaryContainer;
    final frente =
        _esParticular ? scheme.onSecondaryContainer : scheme.onPrimaryContainer;
    final etiqueta =
        _esParticular ? 'Particular' : 'Hab ${_lista.join(' · Hab ')}';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _esParticular ? Icons.person_outline : Icons.hotel,
              size: 14,
              color: frente,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: frente,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
