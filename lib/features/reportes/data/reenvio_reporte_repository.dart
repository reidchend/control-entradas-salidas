import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/pos_cierre_models.dart';
import '../../pos/data/reporte_cierre_texto.dart';
import '../../whatsapp/data/whatsapp_providers.dart';
import '../../whatsapp/data/whatsapp_repository.dart';

/// Reenvío de reportes de cierre YA GUARDADOS por WhatsApp.
///
/// Regenera el texto exacto que se envió (o intentó enviar) al cerrar el
/// turno, desde los JSON almacenados en `pos_cierres`, y lo manda al grupo
/// de reportes del bot. Si el bot no responde, el repositorio de WhatsApp
/// encola el mensaje en la bandeja de reintentos (mismo flujo que el POS).
class ReenvioReporteRepository {
  ReenvioReporteRepository(this._wa);

  final WhatsappRepository _wa;

  /// Reenvía el reporte simple (mensaje de texto).
  Future<bool> reenviarSimple(CierreCaja c) =>
      _wa.enviarReporteSimple(reporteSimpleTexto(c));

  /// Reenvía el reporte detallado como archivo .txt.
  Future<bool> reenviarDetallado(CierreCaja c) {
    final fecha = c.cerradaEn.length >= 10
        ? c.cerradaEn.substring(0, 10).replaceAll('-', '')
        : 'sinfecha';
    return _wa.enviarReporteDetallado(
      fileName: 'cierre_${c.sesionId}_$fecha.txt',
      content: reporteDetalladoTexto(c),
      caption:
          'Cierre turno #${c.sesionId} - ${c.usuarioNombre} (reenvío) - Detalle ingredientes',
    );
  }
}

/// Null cuando WhatsApp no está configurado (sin BD o sin bot).
final reenvioReporteRepoProvider = Provider<ReenvioReporteRepository?>((ref) {
  final wa = ref.watch(whatsappRepoProvider);
  return wa == null ? null : ReenvioReporteRepository(wa);
});
