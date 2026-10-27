import 'package:flutter/material.dart';

import 'package:control_entradas_salidas/core/utils/cantidades.dart';
import 'package:control_entradas_salidas/features/producciones/data/producciones_repository.dart';

/// Panel para decidir si una entrada de producción suma a un lote abierto de
/// la misma receta o si crea una producción nueva.
///
/// Reemplaza al dropdown fácil de ignorar que estaba al final del formulario:
/// la pregunta va explícita ("¿Sumar a un lote abierto o crear uno nuevo?"),
/// cada lote es una tarjeta grande y tocable con su cantidad y fecha, y si ya
/// hay lotes abiertos se pre-selecciona el más reciente para que vincular sea
/// el camino por defecto — el descuido más común era crear un lote nuevo sin
/// querer.
class LoteSelectorPanel extends StatefulWidget {
  const LoteSelectorPanel({
    super.key,
    required this.repo,
    required this.recetaId,
    required this.produccionId,
    required this.onChanged,
  });

  final ProduccionesRepository repo;

  /// Receta cuyos lotes pendientes se listan (los lotes dependen de la receta).
  final int? recetaId;

  /// Producción seleccionada actualmente; `null` significa "lote nuevo".
  final int? produccionId;

  /// Notifica la selección: `null` = crear producción nueva.
  final ValueChanged<int?> onChanged;

  @override
  State<LoteSelectorPanel> createState() => _LoteSelectorPanelState();
}

class _LoteSelectorPanelState extends State<LoteSelectorPanel> {
  late Future<List<ProduccionInfo>> _future;
  bool _autoAplicado = false;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  @override
  void didUpdateWidget(LoteSelectorPanel old) {
    super.didUpdateWidget(old);
    if (old.recetaId != widget.recetaId) {
      // Cambió la receta: los lotes a ofrecer son otros.
      _autoAplicado = false;
      _future = _cargar();
    }
  }

  Future<List<ProduccionInfo>> _cargar() async {
    final recetaId = widget.recetaId;
    if (recetaId == null) return [];
    final pendientes = await widget.repo.getProduccionesPorEstado('pendiente');
    final lotes = pendientes.where((p) => p.recetaId == recetaId).toList();
    return lotes;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.recetaId == null) return const SizedBox.shrink();

    return FutureBuilder<List<ProduccionInfo>>(
      future: _future,
      builder: (context, snap) {
        final lotes = snap.data ?? const <ProduccionInfo>[];
        if (lotes.isEmpty) return _avisoSinLotes(context);
        return _opciones(context, lotes);
      },
    );
  }

  /// Aviso claro para cuando no hay nada que decidir: esta entrada crea un
  /// lote nuevo (igual que antes, pero ahora se anuncia).
  Widget _avisoSinLotes(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No hay lotes abiertos de esta receta: esta entrada crea una producción nueva.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _opciones(BuildContext context, List<ProduccionInfo> lotes) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿Sumar a un lote abierto o crear uno nuevo?',
          style: texto.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final l in lotes)
          _tarjeta(
            context: context,
            scheme: scheme,
            seleccionada: widget.produccionId == l.id,
            icono: Icons.link,
            titulo: 'Sumar al Lote #${l.id}',
            subtitulo: '${formatearCantidad(l.cantidad)} en el lote'
                ' · abierto ${_fmtFecha(l.fechaProduccion)}'
                ' · ${l.usuario ?? 'Sistema'}',
            onTap: () => widget.onChanged(l.id),
          ),
        _tarjeta(
          context: context,
          scheme: scheme,
          seleccionada: widget.produccionId == null,
          icono: Icons.add_circle_outline,
          titulo: 'Producción nueva',
          subtitulo: 'Crear un lote aparte con esta entrada',
          onTap: () => widget.onChanged(null),
        ),
      ],
    );
  }

  /// Tarjeta tocable en todo su ancho: el lote se ve, se lee y se elige con
  /// un toque, sin dropdown escondido.
  Widget _tarjeta({
    required BuildContext context,
    required ColorScheme scheme,
    required bool seleccionada,
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: seleccionada
                ? Color.alphaBlend(
                    scheme.primary.withValues(alpha: 0.08), scheme.surface)
                : scheme.surface,
            border: Border.all(
              color: seleccionada ? scheme.primary : scheme.outlineVariant,
              width: seleccionada ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icono,
                  size: 22,
                  color:
                      seleccionada ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                seleccionada
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 20,
                color: seleccionada ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtFecha(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.day}/${d.month} ${p(d.hour)}:${p(d.minute)}';
  }
}
