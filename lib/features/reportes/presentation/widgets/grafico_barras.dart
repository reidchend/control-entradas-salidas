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

    if (barras.isEmpty) {
      return Container(
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child:
            Text(vacioTexto, style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }

    return Container(
      height: altura,
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
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
    );
  }
}
