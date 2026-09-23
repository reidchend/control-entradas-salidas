import 'package:flutter/material.dart';

import '../../../../core/models/pos_cierre_models.dart';
import '../../../../core/models/pos_models.dart';
enum CierreTurnoResultado {
  /// El usuario confirmó el cierre (guarda, cierra sesión; el WhatsApp se
  /// envía después de la persistencia desde el flujo llamador).
  confirmar,

  /// El usuario canceló o solo quiere salir sin cerrar.
  cancelar,
}

/// Diálogo de cierre de turno con corte de inventario.
/// Muestra resumen y aviso por turno corto (<8h). Al confirmar, devuelve
/// `confirmar`; la persistencia y el envío de WhatsApp los hace el flujo
/// llamador DESPUÉS, para no enviar el reporte sin haber guardado el cierre.
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

class _CierreTurnoDialog extends StatefulWidget {
  const _CierreTurnoDialog({
    required this.cierre,
    required this.sesion,
  });

  final CierreCaja cierre;
  final PosSesion sesion;

  @override
  State<_CierreTurnoDialog> createState() => _CierreTurnoDialogState();
}

class _CierreTurnoDialogState extends State<_CierreTurnoDialog> {
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

  String _fmtNum(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
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

            // Nota
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Al confirmar se cierra el turno y se guarda el corte. '
                      'Los reportes se envían por WhatsApp automáticamente.',
                      style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Botón único de confirmar
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check_circle),
                label: const Text('Confirmar cierre'),
                onPressed: () =>
                    Navigator.pop(context, CierreTurnoResultado.confirmar),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, CierreTurnoResultado.cancelar),
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
      final dt = DateTime.parse(iso).toLocal();
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