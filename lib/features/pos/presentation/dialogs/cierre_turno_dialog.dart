import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_cierre_models.dart';
import '../../../../core/models/pos_models.dart';
import '../../../../features/whatsapp/data/whatsapp_providers.dart';

/// Resultado del diálogo de cierre de turno.
enum CierreTurnoResultado {
  /// El usuario confirmó el cierre (guarda, envía WhatsApp automático, cierra sesión).
  confirmar,

  /// El usuario canceló o solo quiere salir sin cerrar.
  cancelar,
}

/// Diálogo de cierre de turno con corte de inventario.
/// Muestra resumen, aviso por turno corto (<8h), y requiere tipear "CONFIRMAR".
/// Al confirmar, envía los reportes por WhatsApp automáticamente y cierra la sesión.
Future<CierreTurnoResultado?> showCierreTurnoDialog(
  BuildContext context,
  CierreCaja cierre,
  PosSesion sesion,
) async {
  return await showDialog<CierreTurnoResultado>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CierreTurnoDialog(cierre: cierre, sesion: sesion),
  );
}

class _CierreTurnoDialog extends ConsumerStatefulWidget {
  const _CierreTurnoDialog({
    required this.cierre,
    required this.sesion,
  });

  final CierreCaja cierre;
  final PosSesion sesion;

  @override
  ConsumerState<_CierreTurnoDialog> createState() => _CierreTurnoDialogState();
}

class _CierreTurnoDialogState extends ConsumerState<_CierreTurnoDialog> {
  final _confirmCtrl = TextEditingController();
  bool _confirmarHabilitado = false;
  bool _enviando = false;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _onConfirmChange(String value) {
    setState(() {
      _confirmarHabilitado = value.trim() == 'CONFIRMAR';
    });
  }

  String _fmtNum(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  bool get _turnoCorto {
    final abierta = DateTime.tryParse(widget.sesion.abiertaEn ?? '');
    if (abierta == null) return false;
    final duracion = DateTime.now().difference(abierta);
    return duracion.inHours < 8;
  }

  String _duracionTexto() {
    final abierta = DateTime.tryParse(widget.sesion.abiertaEn ?? '');
    if (abierta == null) return 'Desconocida';
    final duracion = DateTime.now().difference(abierta);
    final h = duracion.inHours;
    final m = duracion.inMinutes % 60;
    return '${h}h ${m}m';
  }

  /// Genera el texto del reporte simple para WhatsApp
  String _generarReporteSimpleTexto() {
    final c = widget.cierre;
    final sb = StringBuffer();
    sb.writeln('📊 *CIERRE DE TURNO*');
    sb.writeln('Cajero: ${c.usuarioNombre}');
    sb.writeln('Apertura: ${_fmtFecha(c.abiertaEn)}');
    sb.writeln('Cierre: ${_fmtFecha(c.cerradaEn)}');
    sb.writeln('Duración: ${_duracionTexto()}');
    sb.writeln('');
    sb.writeln('💰 *CAJA*');
    sb.writeln('Inicial: \$${_fmtNum(c.cajaInicial)}');
    sb.writeln('Ventas:  \$${_fmtNum(c.totalVentas)}');
    sb.writeln('──────────────');
    sb.writeln('Final:   \$${_fmtNum(c.cajaFinal)}');
    sb.writeln('');
    sb.writeln('📦 *VENTAS POR PRODUCTO*');
    for (final l in c.reporteSimple.lineas) {
      sb.writeln('• ${l.nombre} (${l.categoria})');
      sb.writeln('  ${_fmtNum(l.cantidad)} x \$${_fmtNum(l.precioUnitario)} = \$${_fmtNum(l.total)}');
    }
    sb.writeln('');
    sb.writeln('TOTAL: \$${_fmtNum(c.reporteSimple.totalGeneral)}');
    sb.writeln('');
    sb.writeln('_Lycoris POS_');
    return sb.toString();
  }

  /// Genera el contenido del reporte detallado (.txt) para WhatsApp
  String _generarReporteDetalladoTexto() {
    final c = widget.cierre;
    final sb = StringBuffer();
    sb.writeln('CIERRE DE TURNO - DETALLADO');
    sb.writeln('============================');
    sb.writeln('');
    sb.writeln('Cajero: ${c.usuarioNombre}');
    sb.writeln('Apertura: ${_fmtFecha(c.abiertaEn)}');
    sb.writeln('Cierre: ${_fmtFecha(c.cerradaEn)}');
    sb.writeln('Duración: ${_duracionTexto()}');
    sb.writeln('');
    sb.writeln('CAJA');
    sb.writeln('----');
    sb.writeln('Inicial: ${_fmtNum(c.cajaInicial)}');
    sb.writeln('Ventas:  ${_fmtNum(c.totalVentas)}');
    sb.writeln('Final:   ${_fmtNum(c.cajaFinal)}');
    sb.writeln('');
    sb.writeln('DESGLOSE POR INGREDIENTE');
    sb.writeln('------------------------');
    for (final d in c.reporteDetallado.desgloses) {
      sb.writeln('');
      sb.writeln('Ingrediente: ${d.ingrediente}');
      sb.writeln('  Total consumido: ${_fmtNum(d.totalConsumido)}');
      sb.writeln('  Stock final:     ${_fmtNum(d.stockFinal)}');
      sb.writeln('  Usos:');
      for (final u in d.usos) {
        sb.writeln('    - ${u.plato}: ${_fmtNum(u.cantidad)}');
      }
    }
    sb.writeln('');
    sb.writeln('============================');
    sb.writeln('Lycoris POS');
    return sb.toString();
  }

  Future<void> _confirmarYEnviar() async {
    final waRepo = ref.read(whatsappRepoProvider);
    if (waRepo == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp no configurado; cierre sin envío')),
      );
      Navigator.pop(context, CierreTurnoResultado.confirmar);
      return;
    }

    setState(() => _enviando = true);

    try {
      final reporteSimple = _generarReporteSimpleTexto();
      final reporteDetallado = _generarReporteDetalladoTexto();
      final fileName = 'cierre_${widget.sesion.id}_${DateTime.now().millisecondsSinceEpoch}.txt';

      // Enviar reporte simple (texto)
      await waRepo.enviarReporteSimple(reporteSimple);

      // Enviar reporte detallado (documento .txt)
      await waRepo.enviarReporteDetallado(
        fileName: fileName,
        content: reporteDetallado,
        caption: 'Cierre de turno - Detalle ingredientes',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reportes enviados por WhatsApp ✅')),
      );

      Navigator.pop(context, CierreTurnoResultado.confirmar);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error enviando WhatsApp: $e; cierre continúa')),
      );
      Navigator.pop(context, CierreTurnoResultado.confirmar);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = widget.cierre;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.point_of_sale, color: scheme.primary),
          const SizedBox(width: 8),
          const Text('Cierre de Turno'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Aviso turno corto
            if (_turnoCorto) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Turno corto: ${_duracionTexto()} (< 8h). '
                        'Verifica que el corte sea correcto antes de confirmar.',
                        style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Resumen de caja
            Text('Resumen del corte', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ResumenRow(label: 'Caja inicial', valor: '\$${_fmtNum(c.cajaInicial)}'),
            _ResumenRow(label: 'Total ventas', valor: '\$${_fmtNum(c.totalVentas)}'),
            const Divider(height: 16),
            _ResumenRow(
              label: 'Caja final',
              valor: '\$${_fmtNum(c.cajaFinal)}',
              bold: true,
              color: scheme.primary,
            ),
            const SizedBox(height: 16),

            // Detalles de sesión
            Text('Detalles de la sesión', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ResumenRow(label: 'Cajero', valor: c.usuarioNombre),
            _ResumenRow(label: 'Apertura', valor: _fmtFecha(c.abiertaEn)),
            _ResumenRow(label: 'Cierre', valor: _fmtFecha(c.cerradaEn)),
            _ResumenRow(label: 'Duración', valor: _duracionTexto()),
            const SizedBox(height: 16),

            // Nota de envío automático
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Al confirmar, se envían los reportes (simple + detallado) por WhatsApp automáticamente.',
                      style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Confirmación por texto
            Text(
              'Para confirmar el cierre, escribe "CONFIRMAR" en el campo:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmCtrl,
              onChanged: _onConfirmChange,
              decoration: InputDecoration(
                hintText: 'CONFIRMAR',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                counterText: '',
              ),
              maxLength: 9,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),

            // Botón único de confirmar (envía WhatsApp + cierra)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(_enviando ? 'Enviando y cerrando...' : 'Confirmar cierre y enviar WhatsApp'),
                onPressed: _confirmarHabilitado && !_enviando
                    ? _confirmarYEnviar
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _enviando
                  ? null
                  : () => Navigator.pop(context, CierreTurnoResultado.cancelar),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtFecha(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _ResumenRow extends StatelessWidget {
  const _ResumenRow({
    required this.label,
    required this.valor,
    this.bold = false,
    this.color,
  });

  final String label;
  final String valor;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: color,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(valor, style: style),
        ],
      ),
    );
  }
}