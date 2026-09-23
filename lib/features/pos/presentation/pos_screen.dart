import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/pos_cierre_models.dart';
import '../../../core/models/pos_models.dart';
import '../../../core/updater/auto_update_checker.dart';
import '../../../features/whatsapp/data/whatsapp_providers.dart';
import '../data/pos_providers.dart';
import '../data/pos_session.dart';
import 'comanda_screen.dart';
import 'config_screen.dart';
import 'dialogs/cierre_turno_dialog.dart';
import 'dialogs/nuevo_cajero_dialog.dart';
import 'dialogs/pin_dialog.dart';
import 'habitaciones_screen.dart';
import 'mesas_screen.dart';
import 'pos_home_screen.dart';
import 'ventas_screen.dart';
import 'widgets/usuario_card.dart';

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
    if (sesion == null) return const _LoginView();
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
  PosHabitacion? _habitacion;

  /// true si la sesión tiene turno de caja abierto o es usuario
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

  void _abrirHabitacion(PosHabitacion h) {
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

  /// Muestra diálogo para elegir: cerrar turno completo, cambiar cajero, o cancelar.
  Future<void> _mostrarOpcionesCierre() async {
    final sesionActiva = ref.read(posSessionProvider);
    if (sesionActiva == null || sesionActiva.sesionId <= 0) return;

    final opcion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Opciones de sesión'),
        content: const Text('¿Qué deseas hacer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancelar'),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cambiar_cajero'),
            child: const Text('Cambiar cajero\n(turno queda abierto)'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'cerrar_turno'),
            child: const Text('Cerrar turno\n(corte + WhatsApp)'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (opcion == 'cambiar_cajero') {
      // Sale sin cerrar: turno queda abierto en BD para retomar luego
      ref.read(posSessionProvider.notifier).salirSinCerrar();
    } else if (opcion == 'cerrar_turno') {
      // Flujo completo: cierre + WhatsApp + cerrar sesión
      await _cerrarSesionCompleto();
    }
  }

  Future<void> _cerrarSesionCompleto() async {
    final sesionActiva = ref.read(posSessionProvider);
    if (sesionActiva == null || sesionActiva.sesionId <= 0) return;

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
    final sesionData = await repo.getSesionActivaDeUsuario(sesionActiva.usuario.id);
    if (!mounted) return;
    Navigator.pop(context); // cerrar loading
    if (sesionData == null) return;

    // 3. Mostrar diálogo de cierre
    final resultado = await showCierreTurnoDialog(context, cierre, sesionData.sesion);
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

    // 5. Cerrar la sesión local (turno ya cerrado en BD)
    await ref.read(posSessionProvider.notifier).cerrarSesion();
    if (!mounted) return;

    // 6. Enviar reportes por WhatsApp (post-persistencia).
    //    Si falla, solo avisamos: el cierre ya quedó registrado y el turno cerrado.
    final waRepo = ref.read(whatsappRepoProvider);
    if (waRepo == null) {
      Navigator.pop(context); // cerrar loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cierre realizado. WhatsApp no configurado; sin envío')),
      );
      return;
    }

    try {
      final reporteSimple = _generarReporteSimpleTexto(cierre);
      final reporteDetallado = _generarReporteDetalladoTexto(cierre);
      final fileName = 'cierre_${cierre.sesionId}_${DateTime.now().millisecondsSinceEpoch}.txt';

      await waRepo.enviarReporteSimple(reporteSimple);
      await waRepo.enviarReporteDetallado(
        fileName: fileName,
        content: reporteDetallado,
        caption: 'Cierre de turno - Detalle ingredientes',
      );
      if (!mounted) return;
      Navigator.pop(context); // cerrar loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cierre realizado; reportes enviados por WhatsApp ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // cerrar loading
      ScaffoldMessenger.of(context).showSnackBar(
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
          sesion: s,
          mesa: _mesa,
          habitacion: _habitacion,
          onBack: () => _go(_PosStage.home),
          onLogout: _mostrarOpcionesCierre,
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

  String _fmtNum(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  String _duracionCierre(CierreCaja c) {
    final a = DateTime.tryParse(c.abiertaEn);
    final b = DateTime.tryParse(c.cerradaEn);
    if (a == null || b == null) return 'Desconocida';
    final d = b.difference(a);
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  String _fmtFechaReporte(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  /// Genera el texto del reporte simple para WhatsApp
  String _generarReporteSimpleTexto(CierreCaja c) {
    final sb = StringBuffer();
    sb.writeln('📊 *CIERRE DE TURNO*');
    sb.writeln('Cajero: ${c.usuarioNombre}');
    sb.writeln('Apertura: ${_fmtFechaReporte(c.abiertaEn)}');
    sb.writeln('Cierre: ${_fmtFechaReporte(c.cerradaEn)}');
    sb.writeln('Duración: ${_duracionCierre(c)}');
    sb.writeln('');
    sb.writeln('💰 *CAJA*');
    sb.writeln('Inicial: \$${_fmtNum(c.cajaInicial)}');
    sb.writeln('Ventas:  \$${_fmtNum(c.totalVentas)}');
    sb.writeln('──────────────');
    sb.writeln('Final:   \$${_fmtNum(c.cajaFinal)}');
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
        sb.writeln('  ${_fmtNum(l.cantidad)} x \$${_fmtNum(l.precioUnitario)} = *\$${_fmtNum(l.total)}*');
      }
      sb.writeln('  *Subtotal: \$${_fmtNum(subtotal)}*');
    }
    sb.writeln('');
    final contornos = c.reporteSimple.contornos;
    if (contornos.isNotEmpty) {
      sb.writeln('🍽️ *CONTORNOS SERVIDOS*');
      for (final cn in contornos) {
        sb.writeln('  ${cn.nombre}: ${_fmtNum(cn.cantidad)}');
      }
      sb.writeln('');
    }
    sb.writeln('💰 *TOTAL GENERAL: \$${_fmtNum(c.reporteSimple.totalGeneral)}*');
    sb.writeln('');
    sb.writeln('_Lycoris POS_');
    return sb.toString();
  }

  /// Genera el contenido del reporte detallado (.txt) para WhatsApp
  String _generarReporteDetalladoTexto(CierreCaja c) {
    final sb = StringBuffer();
    sb.writeln('CIERRE DE TURNO - DETALLADO');
    sb.writeln('============================');
    sb.writeln('');
    sb.writeln('Cajero: ${c.usuarioNombre}');
    sb.writeln('Apertura: ${_fmtFechaReporte(c.abiertaEn)}');
    sb.writeln('Cierre: ${_fmtFechaReporte(c.cerradaEn)}');
    sb.writeln('Duración: ${_duracionCierre(c)}');
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
}

// ===========================================================================
// Login PIN
// ===========================================================================

class _LoginView extends ConsumerStatefulWidget {
  const _LoginView();

  @override
  ConsumerState<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<_LoginView> {
  int? _selectedId;

  Future<void> _login(PosUsuario u) async {
    if (u.pinHash != null && u.pinHash!.isNotEmpty) {
      final result = await showPinDialog(context, u);
      // El diálogo ya inicia la sesión internamente con el PIN. Solo
      // invalidamos la lista si se canceló o el PIN fue incorrecto.
      if (result == null || result == SesionLoginResult.pinIncorrecto) {
        if (mounted) ref.invalidate(usuariosProvider);
      }
      return;
    }
    await ref.read(posSessionProvider.notifier).iniciarSesion(u);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final usuarios = ref.watch(usuariosProvider);
    final turnosActivos =
        ref.watch(turnosActivosProvider).valueOrNull ?? <int>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lycoris POS'),
        leading: Image.asset(
          'assets/icono_azul.png',
          width: 30,
          height: 30,
          fit: BoxFit.cover,
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.storefront, size: 40, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Lycoris POS',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Seleccione el cajero',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 24),
              usuarios.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (lista) => lista.isEmpty
                    ? _sinCajeros()
                    : Column(
                        children: [
                          for (final u in lista) ...[
                            UsuarioCard(
                              usuario: u,
                              selected: u.id == _selectedId,
                              turnoAbierto: turnosActivos.contains(u.id),
                              onTap: () {
                                setState(() => _selectedId = u.id);
                                _login(u);
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 8),
                          _loginButton(lista),
                        ],
                      ),
            ),
          ],
          ),
        ),
          ),
          // Verificar actualizaciones antes del login (Windows/Android).
          const Align(
            alignment: Alignment.topRight,
            child: AutoUpdateChecker(),
          ),
        ],
      ),
    );
  }

  Widget _sinCajeros() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.person_off_outlined, size: 48),
            const SizedBox(height: 8),
            const Text('No hay cajeros registrados',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Agregue uno con el botón de abajo',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showNuevoCajeroDialog(context),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Nuevo cajero'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginButton(List<PosUsuario> lista) {
    final selected = lista.where((u) => u.id == _selectedId).firstOrNull;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: selected == null
                ? null
                : () {
                    setState(() => _selectedId = selected.id);
                    _login(selected);
                  },
            icon: const Icon(Icons.login),
            label: Text(selected == null
                ? 'Iniciar sesión'
                : 'Iniciar sesión como ${selected.nombre}'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Nuevo cajero',
          onPressed: () => showNuevoCajeroDialog(context),
          icon: const Icon(Icons.person_add_alt_1),
        ),
      ],
    );
  }
}
