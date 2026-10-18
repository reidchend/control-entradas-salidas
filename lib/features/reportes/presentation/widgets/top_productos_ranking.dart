import 'package:flutter/material.dart';

/// Métrica principal de un ranking de productos.
enum TopMetrica { facturacion, cantidad }

/// Tarjeta con el ranking Top de productos: medallas para el podio, barra
/// proporcional al líder y ambas métricas visibles (dinero y unidades).
class TopProductosRanking extends StatelessWidget {
  const TopProductosRanking({
    super.key,
    required this.titulo,
    required this.icono,
    required this.color,
    required this.metrica,
    required this.productos,
  });

  final String titulo;
  final IconData icono;
  final Color color;
  final TopMetrica metrica;

  /// Filas ya ordenadas por la [metrica] principal (la de mayor a menor).
  final List<Map<String, dynamic>> productos;

  double _principal(Map<String, dynamic> p) => metrica == TopMetrica.facturacion
      ? (p['total'] as num?)?.toDouble() ?? 0.0
      : (p['cantidad'] as num?)?.toDouble() ?? 0.0;

  double _secundaria(Map<String, dynamic> p) => metrica == TopMetrica.facturacion
      ? (p['cantidad'] as num?)?.toDouble() ?? 0.0
      : (p['total'] as num?)?.toDouble() ?? 0.0;

  String _fmtPrincipal(Map<String, dynamic> p) => metrica == TopMetrica.facturacion
      ? '\$${_principal(p).toStringAsFixed(2)}'
      : '${_fmtCantidad(_principal(p))} und';

  String _fmtSecundaria(Map<String, dynamic> p) => metrica == TopMetrica.facturacion
      ? '${_fmtCantidad(_secundaria(p))} und'
      : '\$${_secundaria(p).toStringAsFixed(2)}';

  static String _fmtCantidad(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(3);

  static Color _colorMedalla(int posicion) => switch (posicion) {
        1 => const Color(0xFFE0A100),
        2 => const Color(0xFF9E9E9E),
        3 => const Color(0xFFB26A2E),
        _ => const Color(0xFF6B7280),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;

    // Las filas vienen ordenadas de mayor a menor por la métrica principal.
    final double maxVal =
        productos.isNotEmpty ? _principal(productos.first) : 0.0;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: color.withValues(alpha: 0.10),
            child: Row(
              children: [
                Icon(icono, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(titulo,
                      style: texto.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold, color: color)),
                ),
              ],
            ),
          ),
          if (productos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('Sin datos en el período',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            )
          else ...[
            for (var i = 0; i < productos.length; i++)
              _Fila(
                posicion: i + 1,
                nombre: productos[i]['nombre'] as String? ?? 'Producto',
                principal: _fmtPrincipal(productos[i]),
                secundaria: _fmtSecundaria(productos[i]),
                avance:
                    maxVal > 0 ? _principal(productos[i]) / maxVal : 0.0,
                scheme: scheme,
                texto: texto,
              ),
          ],
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.posicion,
    required this.nombre,
    required this.principal,
    required this.secundaria,
    required this.avance,
    required this.scheme,
    required this.texto,
  });

  final int posicion;
  final String nombre;
  final String principal;
  final String secundaria;
  final double avance;
  final ColorScheme scheme;
  final TextTheme texto;

  @override
  Widget build(BuildContext context) {
    final colorMedalla = TopProductosRanking._colorMedalla(posicion);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorMedalla.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Text('$posicion',
                    style: texto.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold, color: colorMedalla)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texto.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text(principal,
                  style: texto.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: scheme.primary)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: avance.clamp(0.0, 1.0).toDouble(),
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: colorMedalla,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(secundaria,
                  style: texto.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
