import 'package:flutter/material.dart';

import '../../data/historial_repository.dart';

/// Card de entrada (porta `_create_entrada_card` de
/// `historial_facturas_view.py`): nombre, cantidad + badge de peso y hora.
class EntradaCard extends StatelessWidget {
  const EntradaCard({super.key, required this.entrada});

  final EntradaPorFecha entrada;

  String _fmtHora(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = entrada;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline, color: Colors.green, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.nombre,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      e.cantidadTexto,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.primary),
                    ),
                    if (e.esPesable && e.pesoTotal > 0) ...[
                      const SizedBox(width: 6),
                      _pesoBadge(scheme, e),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text(
            _fmtHora(e.fecha),
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _pesoBadge(ColorScheme scheme, EntradaPorFecha e) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        '${e.pesoTotal.toStringAsFixed(3)} kg',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: scheme.tertiary,
        ),
      ),
    );
  }
}
