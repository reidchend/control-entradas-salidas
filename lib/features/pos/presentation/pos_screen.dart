import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/pos_cierre_models.dart';
import '../../../core/models/pos_models.dart';
import '../../../core/updater/auto_update_checker.dart';
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

  Future<void> _cerrarSesion() async {
    final sesionActiva = ref.read(posSessionProvider);
    if (sesionActiva == null || sesionActiva.sesionId <= 0) return;

    final sesionId = sesionActiva.sesionId;
    final repo = ref.read(posRepoProvider)!;

    // 1. Generar el cierre (calcula totales y reportes)
    CierreCaja cierre;
    try {
      cierre = await repo.generarCierre(sesionId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generando cierre: $e')),
      );
      return;
    }

    // 2. Obtener la sesión para mostrar detalles
    final sesionData = await repo.getSesionActivaDeUsuario(sesionActiva.usuario.id);
    if (!mounted) return;
    if (sesionData == null) return;

    // 3. Mostrar diálogo de cierre
    final resultado = await showCierreTurnoDialog(context, cierre, sesionData.sesion);
    if (!mounted) return;

    if (resultado == null || resultado == CierreTurnoResultado.cancelar) {
      return; // Usuario canceló, no hace nada
    }

    // 4. Guardar el cierre en BD
    try {
      await repo.guardarCierre(cierre);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando cierre: $e')),
      );
      return;
    }

    // 5. Acciones post-guardado
    if (resultado == CierreTurnoResultado.enviarYConfirmar) {
      // El diálogo ya envió los reportes y confirmó el cierre
    }

    // 6. Cerrar la sesión (turno + caja)
    await ref.read(posSessionProvider.notifier).cerrarSesion();
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
          onLogout: _cerrarSesion,
        );
      case _PosStage.habitaciones:
        return HabitacionesScreen(
          sesion: s,
          onOpenHabitacion: _abrirHabitacion,
          onBack: () => _go(_PosStage.home),
          onLogout: _cerrarSesion,
        );
      case _PosStage.comanda:
        return ComandaScreen(
          sesion: s,
          mesa: _mesa,
          habitacion: _habitacion,
          onBack: () => _go(_PosStage.home),
          onLogout: _cerrarSesion,
        );
      case _PosStage.ventas:
        return VentasScreen(
          sesion: s,
          onBack: () => _go(_PosStage.home),
          onLogout: _cerrarSesion,
          onCorregirVenta: _corregirVenta,
        );
      case _PosStage.config:
        return ConfigScreen(
          sesion: s,
          onBack: () => _go(_PosStage.home),
          onLogout: _cerrarSesion,
        );
      case _PosStage.home:
        return PosHomeScreen(
          sesion: s,
          onMesas: () => _go(_PosStage.mesas),
          onHabitaciones: () => _go(_PosStage.habitaciones),
          onVentas: () => _go(_PosStage.ventas),
          onConfig: () => _go(_PosStage.config),
          onLogout: _cerrarSesion,
          onAbrirComanda: _abrirComandaActiva,
        );
    }
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
