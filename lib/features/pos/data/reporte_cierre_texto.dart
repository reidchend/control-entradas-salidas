import '../../../core/models/pos_cierre_models.dart';

/// Generación del texto de los reportes de cierre de turno para WhatsApp.
///
/// Es EXACTAMENTE el mismo texto que se enviaba al cerrar el turno desde el
/// POS; vive acá (y no en la pantalla) para poder regenerarlo y reenviarlo
/// también desde el historial de cierres del módulo inventario.

/// Formatea un número: entero sin decimales, o hasta 3 decimales sin ceros
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
  sb.writeln('Cajero: ${c.usuarioNombre}');
  sb.writeln('Apertura: ${fmtFechaCierre(c.abiertaEn)}');
  sb.writeln('Cierre: ${fmtFechaCierre(c.cerradaEn)}');
  sb.writeln('Duración: ${duracionCierreTexto(c)}');
  sb.writeln('');
  sb.writeln('💰 *CAJA*');
  sb.writeln('Inicial: \$${fmtNumCierre(c.cajaInicial)}');
  sb.writeln('Ventas:  \$${fmtNumCierre(c.totalVentas)}');
  sb.writeln('──────────────');
  sb.writeln('Final:   \$${fmtNumCierre(c.cajaFinal)}');
  if (c.reporteSimple.ventasFueraTurno > 0) {
    sb.writeln('');
    sb.writeln('⚠️ *VENTAS FUERA DE TURNO*');
    sb.writeln(
        '${c.reporteSimple.ventasFueraTurno} por \$${fmtNumCierre(c.reporteSimple.montoFueraTurno)} '
        'cobradas con un turno ya cerrado');
    sb.writeln('_No están incluidas en este cierre._');
  }
  sb.writeln('');

  // Agrupar por categoría
  final porCategoria = <String, List<LineaVenta>>{};
  for (final l in c.reporteSimple.lineas) {
    porCategoria.putIfAbsent(l.categoria, () => []).add(l);
  }

  sb.writeln('📦 *VENTAS POR CATEGORÍA*');
  for (final entry in porCategoria.entries) {
    final categoria = entry.key;
    final items = entry.value;
    final subtotal = items.fold<double>(0, (s, l) => s + l.total);

    sb.writeln('');
    sb.writeln('*${categoria.toUpperCase()}*');
    sb.writeln('━━━━━━━━━━━━━━━━━━');
    for (final l in items) {
      sb.writeln('**${l.nombre}**');
      sb.writeln(
          '  ${fmtNumCierre(l.cantidad)} x \$${fmtNumCierre(l.precioUnitario)} = *\$${fmtNumCierre(l.total)}*');
    }
    sb.writeln('  *Subtotal: \$${fmtNumCierre(subtotal)}*');
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
  sb.writeln('💰 *TOTAL GENERAL: \$${fmtNumCierre(c.reporteSimple.totalGeneral)}*');
  sb.writeln('');
  sb.writeln('_Lycoris POS_');
  return sb.toString();
}

/// Contenido del reporte detallado (.txt de WhatsApp, desglose por
/// ingrediente con stock final y usos por plato).
String reporteDetalladoTexto(CierreCaja c) {
  final sb = StringBuffer();
  sb.writeln('CIERRE DE TURNO - DETALLADO');
  sb.writeln('============================');
  sb.writeln('');
  sb.writeln('Cajero: ${c.usuarioNombre}');
  sb.writeln('Apertura: ${fmtFechaCierre(c.abiertaEn)}');
  sb.writeln('Cierre: ${fmtFechaCierre(c.cerradaEn)}');
  sb.writeln('Duración: ${duracionCierreTexto(c)}');
  sb.writeln('');
  sb.writeln('CAJA');
  sb.writeln('----');
  sb.writeln('Inicial: ${fmtNumCierre(c.cajaInicial)}');
  sb.writeln('Ventas:  ${fmtNumCierre(c.totalVentas)}');
  sb.writeln('Final:   ${fmtNumCierre(c.cajaFinal)}');
  if (c.reporteSimple.ventasFueraTurno > 0) {
    sb.writeln('');
    sb.writeln('!! VENTAS FUERA DE TURNO !!');
    sb.writeln('${c.reporteSimple.ventasFueraTurno} por '
        '\$${fmtNumCierre(c.reporteSimple.montoFueraTurno)} cobradas con un turno');
    sb.writeln('ya cerrado; NO están incluidas en este cierre.');
  }
  sb.writeln('');
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
