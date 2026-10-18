import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_cierre_models.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../../pos/data/reporte_cierre_texto.dart';
import '../../data/reenvio_reporte_repository.dart';

enum _TipoReporte { simple, detallado }

/// Diálogo para reenviar el reporte de un cierre ya guardado: vista previa
/// del texto y envío del simple (mensaje) y/o detallado (.txt) al grupo de
/// reportes del bot de WhatsApp.
class ReenviarCierreDialog extends ConsumerStatefulWidget {
  const ReenviarCierreDialog({super.key, required this.cierre});

  final CierreCaja cierre;

  @override
  ConsumerState<ReenviarCierreDialog> createState() =>
      _ReenviarCierreDialogState();
}

class _ReenviarCierreDialogState extends ConsumerState<ReenviarCierreDialog> {
  _TipoReporte _tipo = _TipoReporte.simple;
  bool _enviando = false;

  CierreCaja get _c => widget.cierre;

  String get _preview => _tipo == _TipoReporte.simple
      ? reporteSimpleTexto(_c)
      : reporteDetalladoTexto(_c);

  Future<void> _enviar() async {
    final repo = ref.read(reenvioReporteRepoProvider);
    if (repo == null) {
      showErrorSnackBar(context, 'WhatsApp no configurado en este equipo');
      return;
    }
    setState(() => _enviando = true);
    try {
      final ok = _tipo == _TipoReporte.simple
          ? await repo.reenviarSimple(_c)
          : await repo.reenviarDetallado(_c);
      if (!mounted) return;
      if (ok) {
        showSuccessSnackBar(context, 'Reporte reenviado al grupo de reportes ✅');
        Navigator.pop(context);
      } else {
        // El repositorio de WhatsApp ya encoló el mensaje en la bandeja de
        // reintentos; solo avisamos.
        showInfoSnackBar(
            context, 'El bot no respondió; quedó en cola de reintentos (Bandeja)');
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Error reenviando: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final cajero = _c.usuarioNombre.isNotEmpty
        ? _c.usuarioNombre
        : 'Cajero sin nombre';

    return AlertDialog(
      title: const Text('Reenviar reporte de cierre'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$cajero · Turno #${_c.sesionId} · ${fmtFechaCierre(_c.cerradaEn)}',
              style: texto.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_TipoReporte>(
              segments: const [
                ButtonSegment(
                  value: _TipoReporte.simple,
                  label: Text('Simple (mensaje)'),
                  icon: Icon(Icons.message_outlined, size: 18),
                ),
                ButtonSegment(
                  value: _TipoReporte.detallado,
                  label: Text('Detallado (.txt)'),
                  icon: Icon(Icons.description_outlined, size: 18),
                ),
              ],
              selected: {_tipo},
              onSelectionChanged: _enviando
                  ? null
                  : (s) => setState(() => _tipo = s.first),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _preview,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: _enviando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, size: 18),
          label: Text(_tipo == _TipoReporte.simple
              ? 'Enviar mensaje'
              : 'Enviar .txt'),
          onPressed: _enviando ? null : _enviar,
        ),
      ],
    );
  }
}
