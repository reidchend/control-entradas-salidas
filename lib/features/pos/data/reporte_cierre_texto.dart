import '../../../core/models/pos_cierre_models.dart';

/// Generación del texto de los reportes de cierre de turno para WhatsApp.
///
/// Es EXACTAMENTE el mismo texto que se enviaba al cerrar el turno desde el
/// POS; vive acá (y no en la pantalla) para poder regenerarlo y reenviarlo
/// también desde el historial de cierres del módulo inventario.
///
/// IMPORTANTE: el reporte no incluye montos ni totales en dinero. Solo se
/// informan cantidades vendidas/consumidas, participantes y tiempos.

/// Formatea una cantidad: entero sin decimales, o hasta 3 decimales sin ceros
/// finales (2 → "2", 2.5 → "2.5", 2.500 → "2.5").
String fmtNumCierre(double v) {
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// Duración legible entre apertura y cierre ("9h 21m").
String duracionCierreTexto(CierreCaja c) {
  final a = DateTime.tryParse(c.abiertaEn);
  final b = DateTime.tryParse(c.cerradaEn);
  if (a == null || b == null) return 'Desconocida';
  final d = b.difference(a);
  return '${d.inHours}h ${d.inMinutes % 60}m';
}

/// Fecha ISO → "dd/mm/aaaa hh:mm" (hora local).
String fmtFechaCierre(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}

/// Texto del reporte simple (mensaje de WhatsApp al grupo de reportes).
String reporteSimpleTexto(CierreCaja c) {
  final sb = StringBuffer();
  sb.writeln('📊 *CIERRE DE TURNO*');
  sb.writeln('Apertura: ${fmtFechaCierre(c.abiertaEn)}');
  sb.writeln('Cierre: ${fmtFechaCierre(c.cerradaEn)}');
  sb.writeln('Duración: ${duracionCierreTexto(c)}');
  sb.writeln('');

  if (c.reporteSimple.porUsuario.isNotEmpty) {
    sb.writeln('👥 *PARTICIPANTES*');
    for (final u in c.reporteSimple.porUsuario) {
      sb.writeln('  ${u.nombre}');
    }
    sb.writeln('');
  }

  if (c.reporteSimple.ventasFueraTurno > 0) {
    sb.writeln('⚠️ *VENTAS FUERA DE TURNO*');
    sb.writeln('  ${fmtNumCierre(c.reporteSimple.ventasFueraTurno.toDouble())} '
        'ventas cobradas con un turno ya cerrado');
    sb.writeln('  _No están incluidas en este cierre._');
    sb.writeln('');
  }

  // Agrupar por categoría; se muestra solo la cantidad de cada producto.
  final porCategoria = <String, List<LineaVenta>>{};
  for (final l in c.reporteSimple.lineas) {
    porCategoria.putIfAbsent(l.categoria, () => []).add(l);
  }

  sb.writeln('📦 *VENTAS POR CATEGORÍA*');
  for (final entry in porCategoria.entries) {
    sb.writeln('');
    sb.writeln('*${entry.key.toUpperCase()}*');
    sb.writeln('━━━━━━━━━━━━━━━━━━');
    for (final l in entry.value) {
      sb.writeln('  • *${l.nombre}*: ${fmtNumCierre(l.cantidad)}');
    }
  }
  sb.writeln('');

  final contornos = c.reporteSimple.contornos;
  if (contornos.isNotEmpty) {
    sb.writeln('🍽️ *CONTORNOS SERVIDOS*');
    for (final cn in contornos) {
      sb.writeln('  ${cn.nombre}: ${fmtNumCierre(cn.cantidad)}');
    }
    sb.writeln('');
  }
  sb.writeln('_Lycoris POS_');
  return sb.toString();
}

/// Contenido del reporte detallado (.txt de WhatsApp, desglose por
/// ingrediente con stock final y usos por plato). También sin montos.
String reporteDetalladoTexto(CierreCaja c) {
  final sb = StringBuffer();
  sb.writeln('CIERRE DE TURNO - DETALLADO');
  sb.writeln('============================');
  sb.writeln('');
  sb.writeln('Apertura: ${fmtFechaCierre(c.abiertaEn)}');
  sb.writeln('Cierre: ${fmtFechaCierre(c.cerradaEn)}');
  sb.writeln('Duración: ${duracionCierreTexto(c)}');
  sb.writeln('');
  if (c.reporteSimple.porUsuario.isNotEmpty) {
    sb.writeln('PARTICIPANTES');
    sb.writeln('-----------');
    for (final u in c.reporteSimple.porUsuario) {
      sb.writeln(u.nombre);
    }
    sb.writeln('');
  }
  if (c.reporteSimple.ventasFueraTurno > 0) {
    sb.writeln('VENTAS FUERA DE TURNO');
    sb.writeln('---------------------');
    sb.writeln('${c.reporteSimple.ventasFueraTurno} ventas cobradas con un turno '
        'ya cerrado; NO están incluidas en este cierre.');
    sb.writeln('');
  }
  sb.writeln('DESGLOSE POR INGREDIENTE');
  sb.writeln('------------------------');
  for (final d in c.reporteDetallado.desgloses) {
    sb.writeln('');
    sb.writeln('Ingrediente: ${d.ingrediente}');
    sb.writeln('  Total consumido: ${fmtNumCierre(d.totalConsumido)}');
    sb.writeln('  Stock final:     ${fmtNumCierre(d.stockFinal)}');
    sb.writeln('  Usos:');
    for (final u in d.usos) {
      sb.writeln('    - ${u.plato}: ${fmtNumCierre(u.cantidad)}');
    }
  }
  sb.writeln('');
  sb.writeln('============================');
  sb.writeln('Lycoris POS');
  return sb.toString();
}
