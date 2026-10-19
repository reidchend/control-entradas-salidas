import 'package:flutter/material.dart';

/// Tarjeta de categoría estilo Flet (`usr/views/inventario/categories.py`):
/// card con borde inferior del color de la categoría, avatar circular con la
/// inicial y hover que escala 1.05.
class CategoriaCard extends StatefulWidget {
  const CategoriaCard({
    super.key,
    required this.nombre,
    required this.color,
    required this.onTap,
    this.activo = true,
  });

  final String nombre;
  final String color;
  final VoidCallback onTap;

  /// `false` cuando la categoría está desactivada (`activo = false`): sigue
  /// mostrándose para poder llegar a sus productos, pero marcada como inactiva.
  final bool activo;

  @override
  State<CategoriaCard> createState() => _CategoriaCardState();
}

class _CategoriaCardState extends State<CategoriaCard> {
  double _scale = 1.0;
  double _rotate = 0.0;

  Color _parseColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', '0xFF'));
    return v != null ? Color(v) : Colors.blue;
  }

  void _onEnter(bool entered) {
    setState(() {
      _scale = entered ? 1.05 : 1.0;
      _rotate = entered ? 0.02 : 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final catColor = _parseColor(widget.color);
    final nombre = widget.nombre.isEmpty ? 'SIN NOMBRE' : widget.nombre;
    final inicial = nombre[0].toUpperCase();

    return MouseRegion(
      onEnter: (_) => _onEnter(true),
      onExit: (_) => _onEnter(false),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: AnimatedRotation(
          turns: _rotate,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                    bottom: BorderSide(
                        color: widget.activo ? catColor : colors.outlineVariant,
                        width: 3)),
                boxShadow: [
                  BoxShadow(
                    blurRadius: _scale > 1 ? 15 : 0,
                    color: catColor.withValues(alpha: 0.2),
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.activo
                          ? catColor
                          : colors.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 8,
                          color: catColor.withValues(alpha: 0.3),
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      inicial,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: widget.activo
                            ? Colors.white
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    nombre.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colors.onSurface,
                    ),
                  ),
                  if (!widget.activo) ...[
                    const SizedBox(height: 2),
                    Text(
                      'INACTIVA',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
