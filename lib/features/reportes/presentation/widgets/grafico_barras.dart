import 'package:flutter/material.dart';

import 'grafico_barras_painter.dart';

/// Dato de una barra del gráfico.
class DatoBarra {
  const DatoBarra({
    required this.etiqueta,
    required this.valor,
    this.destacado = false,
  });

  /// Etiqueta del eje X (ej. "18/10" u "8h").
  final String etiqueta;

  /// Valor de la barra (monto en dinero).
  final double valor;

  /// Marca la barra en verde (mejor día / hora pico).
  final bool destacado;
}

/// Gráfico de barras con eje Y en moneda, monto impreso sobre cada barra
/// (en horizontal si hay espacio, rotado si la barra es angosta, y solo si
/// el barra no queda pegada al tope) y etiquetas del eje X espaciadas para
/// que no se pisen.
class GraficoBarras extends StatelessWidget {
  const GraficoBarras({
    super.key,
    required this.barras,
    this.altura = 220,
    this.colorBase,
    this.colorDestacado = const Color(0xFF16A34A),
    this.etiquetasMaximas = 14,
    this.vacioTexto = 'Sin datos para el período',
  });

  final List<DatoBarra> barras;
  final double altura;

  /// Color normal de las barras (por defecto, el primario del tema).
  final Color? colorBase;

  /// Color de la barra destacada (por defecto, verde).
  final Color colorDestacado;

  /// Cantidad máxima de etiquetas del eje X visibles.
  final int etiquetasMaximas;

  final String vacioTexto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // El panel del gráfico usa el mismo fondo que las cards del tema. Antes era
    // `surfaceContainerHighest`, que en el tema claro (#E3DAF4) se veía como un
    // rectángulo gris vacío, igual que un placeholder roto.
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: barras.isEmpty
          ? _Vacio(texto: vacioTexto)
          : SizedBox(
              height: altura,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 12, 4),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: BarrasPainter(
                    barras: barras,
                    colorBase: colorBase ?? scheme.primary,
                    colorDestacado: colorDestacado,
                    etiquetasMaximas: etiquetasMaximas,
                    colorTexto: scheme.onSurfaceVariant,
                    colorRejilla: scheme.outlineVariant,
                  ),
                ),
              ),
            ),
    );
  }
}

/// Estado vacío del gráfico: ícono + mensaje centrados sobre el fondo de la
/// card (sin relleno gris), para que se lea como "acá no hubo ventas" y no
/// como un cuadro roto.
class _Vacio extends StatelessWidget {
  const _Vacio({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 140,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_outlined,
                size: 32, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                texto,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
