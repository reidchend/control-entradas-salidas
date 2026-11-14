import 'package:flutter/material.dart';

/// Tarjeta de entrada del selector de comandas (port mejorado de
/// `ComandasView._build_entry_card`): icono con glow, título, subtítulo,
/// badge/valor opcional y botón "Entrar" con gradiente. Con escala al
/// presionar y riple.
class EntryCard extends StatefulWidget {
  const EntryCard({
    super.key,
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.onTap,
    this.badge,
    this.valor,
  });

  final IconData icon;
  final String titulo;
  final String subtitulo;
  final Color color;
  final VoidCallback onTap;

  /// Texto corto de estado (ej. "3 ocupadas").
  final String? badge;

  /// Monto/cantidad destacado bajo el subtítulo (ej. "Bs 1.200,00").
  final String? valor;

  @override
  State<EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<EntryCard> {
  bool _presionada = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = widget.color;
    final esPequena = MediaQuery.sizeOf(context).width <= 720;

    final anchoTarjeta = esPequena ? 230.0 : 280.0;
    final tamanoIcono = esPequena ? 56.0 : 74.0;
    final tamanoIconoInterno = esPequena ? 30.0 : 38.0;
    final tamanoTitulo = esPequena ? 18.0 : 22.0;
    final paddingInterno = esPequena ? 16.0 : 22.0;
    final espaciadoTitulo = esPequena ? 14.0 : 18.0;

    return AnimatedScale(
      scale: _presionada ? 0.96 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Container(
        width: anchoTarjeta,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              c.withValues(alpha: 0.16),
              scheme.surfaceContainerHigh.withValues(alpha: 0.55),
              c.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _presionada = v),
            child: Padding(
              padding: EdgeInsets.all(paddingInterno),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: tamanoIcono,
                        height: tamanoIcono,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.withValues(alpha: 0.16),
                          boxShadow: [
                            BoxShadow(
                              color: c.withValues(alpha: 0.35),
                              blurRadius: 22,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(widget.icon, size: tamanoIconoInterno, color: c),
                      ),
                      const Spacer(),
                      if (widget.badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: c.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.circle,
                                  size: 8, color: Colors.white),
                              const SizedBox(width: 5),
                              Text(
                                widget.badge!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: espaciadoTitulo),
                  Text(
                    widget.titulo,
                    style: TextStyle(
                      fontSize: tamanoTitulo,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.subtitulo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: esPequena ? 11 : 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (widget.valor != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.valor!,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: espaciadoTitulo),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 11),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [c, c.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: c.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Entrar',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
