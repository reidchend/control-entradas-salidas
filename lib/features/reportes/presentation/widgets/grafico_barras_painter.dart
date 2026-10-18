import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'grafico_barras.dart';

/// Pintor interno de [GraficoBarras]: rejilla con escala en moneda, barras
/// con esquinas redondeadas, monto sobre cada barra y etiquetas del eje X.
class BarrasPainter extends CustomPainter {
  BarrasPainter({
    required this.barras,
    required this.colorBase,
    required this.colorDestacado,
    required this.etiquetasMaximas,
    required this.colorTexto,
    required this.colorRejilla,
  });

  final List<DatoBarra> barras;
  final Color colorBase;
  final Color colorDestacado;
  final int etiquetasMaximas;
  final Color colorTexto;
  final Color colorRejilla;

  static const double _margenIzq = 56;
  static const double _margenDer = 8;
  static const double _margenSup = 22;
  static const double _margenInf = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(
      _margenIzq,
      _margenSup,
      size.width - _margenDer,
      size.height - _margenInf,
    );
    if (area.width <= 10 || area.height <= 10) return;

    final maxValor = barras.fold<double>(0, (m, b) => b.valor > m ? b.valor : m);
    final escala = _escalaBonita(maxValor);
    const divisiones = 4;

    // Rejilla horizontal + etiquetas del eje Y en moneda.
    for (var i = 0; i <= divisiones; i++) {
      final valor = escala * i / divisiones;
      final y = area.bottom - area.height * i / divisiones;
      canvas.drawLine(
        Offset(area.left, y),
        Offset(area.right, y),
        Paint()
          ..color = colorRejilla
          ..strokeWidth = i == 0 ? 1.2 : 1,
      );
      _texto(
        canvas,
        _fmtEje(valor),
        Offset(area.left - 6, y),
        estilo: TextStyle(fontSize: 10, color: colorTexto),
        alinearDerecha: true,
        centrarVertical: true,
      );
    }

    // Barras: separación, ancho y cada cuántas etiquetar en el eje X.
    final n = barras.length;
    final hueco = area.width / n;
    final anchoBarra = math.min(math.max(hueco * 0.62, 3.0), 46.0);
    final montosHorizontales = hueco >= 52;
    var cada = 1;
    while ((hueco * cada < 44 || n / cada > etiquetasMaximas) && cada < n) {
      cada++;
    }

    for (var i = 0; i < n; i++) {
      final barra = barras[i];
      final alto = escala > 0 ? area.height * (barra.valor / escala) : 0.0;
      final centroX = area.left + hueco * (i + 0.5);
      final color = barra.destacado ? colorDestacado : colorBase;
      final topeY = area.bottom - alto;

      if (alto > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              centroX - anchoBarra / 2,
              topeY,
              centroX + anchoBarra / 2,
              area.bottom,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = color,
        );
      }

      _monto(canvas, barra, centroX, topeY, hueco, montosHorizontales, area);

      if (i % cada == 0 || i == n - 1) {
        _texto(
          canvas,
          barra.etiqueta,
          Offset(centroX, area.bottom + 5),
          estilo: TextStyle(fontSize: 9.5, color: colorTexto),
          centrarHorizontal: true,
        );
      }
    }
  }

  /// Imprime el monto sobre la barra: horizontal si cabe, rotado 90° si la
  /// barra es angosta y hay altura libre, y sin monto si no cabe ninguno.
  void _monto(
    Canvas canvas,
    DatoBarra barra,
    double centroX,
    double topeY,
    double hueco,
    bool horizontal,
    Rect area,
  ) {
    if (barra.valor <= 0) return;
    final estilo = TextStyle(
      fontSize: 9.5,
      fontWeight: barra.destacado ? FontWeight.w700 : FontWeight.w500,
      color: barra.destacado ? colorDestacado : colorTexto,
    );
    final txt = _fmtMonto(barra.valor);
    final tp = TextPainter(
      text: TextSpan(text: txt, style: estilo),
      textDirection: TextDirection.ltr,
    )..layout();

    if (horizontal || tp.width <= hueco - 4) {
      _texto(
        canvas,
        txt,
        Offset(centroX, topeY - tp.height - 4),
        estilo: estilo,
        centrarHorizontal: true,
      );
      return;
    }

    // Sin espacio horizontal: texto rotado si la barra no llega al tope.
    final disponible = topeY - area.top;
    if (disponible < tp.width + 6) return;
    canvas.save();
    canvas.translate(centroX - tp.height / 2, topeY - 4);
    canvas.rotate(-math.pi / 2);
    _texto(canvas, txt, Offset.zero, estilo: estilo);
    canvas.restore();
  }

  /// Escala "bonita" (múltiplos de 1/2/5 × 10^n) con 4 divisiones.
  static double _escalaBonita(double max) {
    if (max <= 0) return 1;
    final bruto = max / 4;
    final magnitud =
        math.pow(10, (math.log(bruto) / math.ln10).floor()).toDouble();
    final norm = bruto / magnitud;
    final paso = (norm <= 1
            ? 1.0
            : (norm <= 2 ? 2.0 : (norm <= 5 ? 5.0 : 10.0))) *
        magnitud;
    return (max / paso).ceil() * paso;
  }

  /// Etiqueta del eje Y: moneda compacta ("$850", "$1.5k").
  static String _fmtEje(double v) {
    if (v >= 1000) {
      final k = v / 1000;
      final txt =
          k == k.roundToDouble() ? k.toInt().toString() : k.toStringAsFixed(1);
      return '\$$txt''k';
    }
    final r = (v * 100).roundToDouble() / 100;
    final txt = r == r.roundToDouble() ? r.toInt().toString() : r.toString();
    return '\$$txt';
  }

  /// Monto de la barra: con centavos solo si los tiene, con separador de
  /// miles ("$1,234").
  static String _fmtMonto(double v) {
    if (v != v.roundToDouble()) return '\$${v.toStringAsFixed(2)}';
    return '\$${_conMiles(v.toInt())}';
  }

  static String _conMiles(int n) {
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return n < 0 ? '-$b' : '$b';
  }

  static void _texto(
    Canvas canvas,
    String txt,
    Offset ancla, {
    required TextStyle estilo,
    bool centrarHorizontal = false,
    bool centrarVertical = false,
    bool alinearDerecha = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: txt, style: estilo),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = ancla.dx;
    var dy = ancla.dy;
    if (centrarHorizontal) dx -= tp.width / 2;
    if (alinearDerecha) dx -= tp.width;
    if (centrarVertical) dy -= tp.height / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant BarrasPainter viejo) => true;
}
