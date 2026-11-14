import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/polling_providers.dart';
import '../../../core/data/postgres_providers.dart';
import '../../../core/models/pos_cierre_models.dart';
import '../../../core/models/pos_models.dart';
import '../../../features/whatsapp/data/whatsapp_providers.dart';
import '../data/pos_providers.dart';
import '../data/pos_session.dart';
import '../data/reporte_cierre_texto.dart';
import 'comanda_screen.dart';
import 'config_screen.dart';
import 'dialogs/cierre_turno_dialog.dart';
import 'dialogs/opciones_sesion_dialog.dart';
import 'habitaciones_screen.dart';
import 'login/login_screen.dart';
import 'mesas_screen.dart';
import 'pos_home_screen.dart';
import 'ventas_screen.dart';

/// Diálogo de carga mostrado mientras se genera el cierre de turno.
class _CerrandoSesionDialog extends StatelessWidget {
  const _CerrandoSesionDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Generando corte de caja...\nCalculando totales y reportes',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pantalla del módulo POS.
/// - Sin sesión: login PIN (Fase 6.1) — lista de cajeros, seed admin, alta.
/// - Con sesión: router de etapas (Fase 6.2): selector → mesas/habitaciones →
///   apertura de comanda. Ventas (6.4) con historial y anulación; Config (6.5)
///   con cajeros/mesas/habitaciones/platos/categorías/tasa BCV.
class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(posSessionProvider);
    if (sesion == null) return const LoginScreen();
    return _PosRouter(key: ValueKey(sesion.sesionId), sesion: sesion);
  }
}

// ===========================================================================
// Router por etapas (post-login)
// ===========================================================================

enum _PosStage { home, mesas, habitaciones, comanda, ventas, config }

class _PosRouter extends ConsumerStatefulWidget {
  const _PosRouter({super.key, required this.sesion});
  final PosSesionActiva sesion;

  @override
  ConsumerState<_PosRouter> createState() => _PosRouterState();
}

class _PosRouterState extends ConsumerState<_PosRouter> {
  _PosStage _stage = _PosStage.home;
  PosMesa? _mesa;
  Habitacion? _habitacion;
  List<void Function()> _pollingCancels = [];

  /// Polling de comandas/sesiones para el POS: detecta cuando otro
  /// dispositivo abre/cierra una comanda y refresca `mesasOcupadasProvider`,
  /// `comandasAbiertasProvider`, etc. para que la mesa aparezca como ocupada
  /// en todos los terminales sin necesidad de recargar la pantalla.
  @override
  void initState() {
    super.initState();
    Future(() {
      final db = ref.read(postgresServiceProvider);
      if (db != null && mounted) {
        _pollingCancels = initPollingSubscriptions(ref, db: db);
      }
    });
  }

  @override
  void dispose() {
    for (final cancel in _pollingCancels) {
      cancel();
    }
    super.dispose();
  }
  /// desarrollador (sesionId == 0, pruebas sin turno).
  bool get _tieneTurno =>
      widget.sesion.sesionId > 0 || widget.sesion.usuario.esDesarrollador;

  /// Etapas que requieren turno de caja (no aplicables al usuario
  /// desarrollador, que inicia sesión sin aperturar turno/caja).
  static const _etapasConTurno = {
    _PosStage.mesas,
    _PosStage.habitaciones,
    _PosStage.comanda,
    _PosStage.ventas,
  };

  void _bloquearSinTurno() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sesión sin turno de caja: para operar ventas inicie sesión con un '
          'cajero que abra turno.',
        ),
      ),
    );
  }

  void _go(_PosStage stage) {
    if (!_tieneTurno && _etapasConTurno.contains(stage)) {
      _bloquearSinTurno();
      return;
    }
    setState(() {
      _stage = stage;
      _mesa = null;
      _habitacion = null;
    });
  }

  void _abrirMesa(PosMesa m) {
    if (!_tieneTurno) {
      _bloquearSinTurno();
      return;
    }
    setState(() {
      _mesa = m;
      _habitacion = null;
      _stage = _PosStage.comanda;
    });
  }

  void _abrirHabitacion(Habitacion h) {
    if (!_tieneTurno) {
      _bloquearSinTurno();
      return;
    }
    setState(() {
      _habitacion = h;
      _mesa = null;
      _stage = _PosStage.comanda;
    });
  }

  /// Muestra diálogo para elegir: cambiar usuario o cerrar el turno completo.
  /// Cerrar solo se habilita para el aperturista en la PC principal.
  Future<void> _mostrarOpcionesCierre() async {
    final sesionActiva = ref.read(posSessionProvider);
    if (sesionActiva == null) return;

    // Sesión de desarrollador (sin turno): solo puede salir.
    if (sesionActiva.sesionId <= 0) {
      await ref.read(posSessionProvider.notifier).salirDelTurno();
      return;
    }

    final opcion = await showOpcionesSesionDialog(
      context,
      esAperturista: sesionActiva.esAperturista,
      aperturistaNombre: sesionActiva.aperturistaNombre,
    );

    if (!mounted || opcion == null) return;

    if (opcion == OpcionSesion.cambiarUsuario) {
      // Sale sin cerrar: el turno queda abierto para los demás.
      await ref.read(posSessionProvider.notifier).salirDelTurno();
    } else if (opcion == OpcionSesion.cerrarTurno) {
      if (!sesionActiva.puedeCerrarTurno) return;
      await _cerrarSesionCompleto();
    }
  }

  Future<void> _cerrarSesionCompleto() async {
    final sesionActiva = ref.read(posSessionProvider);
    if (sesionActiva == null || sesionActiva.sesionId <= 0) return;

    // Defensa en profundidad: solo el aperturista desde la PC principal.
    if (!sesionActiva.puedeCerrarTurno) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sesionActiva.aperturistaNombre == null
                ? 'Solo el usuario que abrió el turno puede cerrarlo desde la '
                    'PC principal.'
                : 'Solo ${sesionActiva.aperturistaNombre} puede cerrar el turno '
                    'desde la PC principal.',
          ),
        ),
      );
      return;
    }

    // Mostrar diálogo de carga inmediatamente
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CerrandoSesionDialog(),
    );

    final sesionId = sesionActiva.sesionId;
    final repo = ref.read(posRepoProvider)!;

    // 1. Generar el cierre (calcula totales y reportes) - operación pesada
    CierreCaja cierre;
    try {
      cierre = await repo.generarCierre(sesionId);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // cerrar loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generando cierre: $e')),
      );
      return;
    }

    // 2. Obtener la sesión para mostrar detalles
    final sesionData = await repo.getSesionPorId(sesionId);
    if (!mounted) return;
    Navigator.pop(context); // cerrar loading
    if (sesionData == null) return;

    // 3. Mostrar diálogo de cierre
    final resultado =
        await showCierreTurnoDialog(context, cierre, sesionData);
    if (!mounted) return;

    if (resultado == null || resultado == CierreTurnoResultado.cancelar) {
      return; // Usuario canceló, no hace nada
    }

    // 4. Persistir el cierre y cerrar el turno (transacción atómica).
    //    Si falla, el turno queda abierto y NO se envían reportes, para evitar
    //    el reporte por WhatsApp sin cierre registrado.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CerrandoSesionDialog(),
    );
    try {
      await repo.finalizarCierreYTurno(cierre);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // cerrar loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando cierre; el turno queda abierto: $e')),
      );
      return;
    }

    // Los reportes se generan ANTES de soltar la sesión: estos métodos y
    // `whatsappRepoProvider` viven en esta pantalla, que se desmonta al cerrar.
    final reporteSimple = _generarReporteSimpleTexto(cierre);
    final reporteDetallado = _generarReporteDetalladoTexto(cierre);
    final fileName =
        'cierre_${cierre.sesionId}_${DateTime.now().millisecondsSinceEpoch}.txt';
    final waRepo = ref.read(whatsappRepoProvider);
    if (!mounted) return;

    // 5. Cerrar la sesión local (turno ya cerrado en BD). Al ponerse en null,
    //    PosScreen reconstruye el LoginScreen y ESTA pantalla se desmonta, pero
    //    el diálogo de carga vive en el navigator raíz y no se puede cerrar
    //    con `context` desmontado. Se capturan navigator y messenger mientras
    //    viven para cerrar el diálogo y avisar aunque esta pantalla ya no exista.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(posSessionProvider.notifier).cerrarSesion();

    // 6. Enviar reportes por WhatsApp (post-persistencia).
    //    Si falla, solo avisamos: el cierre ya quedó registrado y el turno cerrado.
    if (waRepo == null) {
      navigator.pop(); // cerrar loading (el navigator sigue vivo)
      messenger.showSnackBar(
        const SnackBar(content: Text('Cierre realizado. WhatsApp no configurado; sin envío')),
      );
      return;
    }

    try {
      await waRepo.enviarReporteSimple(reporteSimple);
      await waRepo.enviarReporteDetallado(
        fileName: fileName,
        content: reporteDetallado,
        caption: 'Cierre de turno - Detalle ingredientes',
      );
      navigator.pop(); // cerrar loading
      messenger.showSnackBar(
        const SnackBar(content: Text('Cierre realizado; reportes enviados por WhatsApp ✅')),
      );
    } catch (e) {
      navigator.pop(); // cerrar loading
      messenger.showSnackBar(
        SnackBar(content: Text('Cierre realizado, pero falló WhatsApp: $e')),
      );
    }
  }

  /// Retoma una comanda activa desde el home (resuelve mesa/habitación por id
  /// y abre la etapa de comanda directamente).
  Future<void> _abrirComandaActiva(int? mesaId, int? habitacionId) async {
    if (!_tieneTurno) {
      _bloquearSinTurno();
      return;
    }
    final repo = ref.read(posRepoProvider)!;
    if (mesaId != null) {
      final m = await repo.getMesaById(mesaId);
      if (m == null) return;
      if (!mounted) return;
      setState(() {
        _mesa = m;
        _habitacion = null;
        _stage = _PosStage.comanda;
      });
    } else if (habitacionId != null) {
      final h = await repo.getHabitacionById(habitacionId);
      if (h == null) return;
      if (!mounted) return;
      setState(() {
        _habitacion = h;
        _mesa = null;
        _stage = _PosStage.comanda;
      });
    }
  }

  /// Después de anular una venta: abre la comanda de la mesa/habitación
  /// devuelta para corregirla y volver a cobrar (port de `VentasView._ir_a_comanda`).
  Future<void> _corregirVenta(int? mesaId, int? habitacionId) async {
    if (!_tieneTurno) {
      _bloquearSinTurno();
      return;
    }
    final repo = ref.read(posRepoProvider)!;
    if (mesaId != null) {
      final m = await repo.getMesaById(mesaId);
      if (m == null) {
        _go(_PosStage.ventas);
        return;
      }
      if (!mounted) return;
      setState(() {
        _mesa = m;
        _habitacion = null;
        _stage = _PosStage.comanda;
      });
    } else if (habitacionId != null) {
      final h = await repo.getHabitacionById(habitacionId);
      if (h == null) {
        _go(_PosStage.ventas);
        return;
      }
      if (!mounted) return;
      setState(() {
        _habitacion = h;
        _mesa = null;
        _stage = _PosStage.comanda;
      });
    } else {
      _go(_PosStage.ventas);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sesion;
    switch (_stage) {
      case _PosStage.mesas:
        return MesasScreen(
          sesion: s,
          onOpenMesa: _abrirMesa,
          onBack: () => _go(_PosStage.home),
          onLogout: _mostrarOpcionesCierre,
        );
      case _PosStage.habitaciones:
        return HabitacionesScreen(
          sesion: s,
          onOpenHabitacion: _abrirHabitacion,
          onBack: () => _go(_PosStage.home),
          onLogout: _mostrarOpcionesCierre,
        );
      case _PosStage.comanda:
        return ComandaScreen(
          key: ValueKey('comanda-${_mesa?.id ?? 0}-${_habitacion?.id ?? 0}'),
          sesion: s,
          mesa: _mesa,
          habitacion: _habitacion,
          onBack: () => _go(_PosStage.home),
          onLogout: _mostrarOpcionesCierre,
          onComandaMovida: _abrirComandaActiva,
        );
      case _PosStage.ventas:
        return VentasScreen(
          sesion: s,
          onBack: () => _go(_PosStage.home),
          onLogout: _mostrarOpcionesCierre,
          onCorregirVenta: _corregirVenta,
        );
      case _PosStage.config:
        return ConfigScreen(
          sesion: s,
          onBack: () => _go(_PosStage.home),
          onLogout: _mostrarOpcionesCierre,
        );
      case _PosStage.home:
        return PosHomeScreen(
          sesion: s,
          onMesas: () => _go(_PosStage.mesas),
          onHabitaciones: () => _go(_PosStage.habitaciones),
          onVentas: () => _go(_PosStage.ventas),
          onConfig: () => _go(_PosStage.config),
          onLogout: _mostrarOpcionesCierre,
          onAbrirComanda: _abrirComandaActiva,
        );
    }
  }

  // -------------------------------------------------------------------------
  // Generación de reportes para WhatsApp (se envían tras persistir el cierre)
  // -------------------------------------------------------------------------

  // La implementación vive en `data/reporte_cierre_texto.dart` para poder
  // reenviar estos MISMOS textos desde el historial de cierres (inventario).

  /// Genera el texto del reporte simple para WhatsApp
  String _generarReporteSimpleTexto(CierreCaja c) => reporteSimpleTexto(c);

  /// Genera el contenido del reporte detallado (.txt) para WhatsApp
  String _generarReporteDetalladoTexto(CierreCaja c) =>
      reporteDetalladoTexto(c);
}

