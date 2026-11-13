import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/data/postgres_guard.dart';
import '../../../../../core/models/pos_models.dart';
import '../../../../configuracion/presentation/widgets/bd_no_disponible.dart';
import '../../../data/pos_dispositivo.dart';
import '../../../data/pos_providers.dart';
import '../../../data/pos_session.dart';
import '../../../data/pos_turno_models.dart';
import '../../../data/reporte_cierre_texto.dart';
import '../../dialogs/nuevo_cajero_dialog.dart';
import '../../dialogs/pin_dialog.dart';
import '../../widgets/usuario_card.dart';

/// Pestaña Personal del login: elegir usuario y abrir/unirse al turno.
///
/// En la PC principal, si no hay turno abierto, el primer usuario que entra lo
/// abre. En Android (u otras terminales) el usuario se une al turno abierto; si
/// no hay ninguno, no puede abrirlo y se le indica que debe hacerse en la PC.
class PersonalPanel extends ConsumerStatefulWidget {
  const PersonalPanel({super.key});

  @override
  ConsumerState<PersonalPanel> createState() => _PersonalPanelState();
}

class _PersonalPanelState extends ConsumerState<PersonalPanel> {
  int? _selectedId;
  bool _entrando = false;

  Future<void> _login(PosUsuario u) async {
    if (_entrando) return;
    setState(() {
      _selectedId = u.id;
      _entrando = true;
    });
    try {
      // Los usuarios con PIN se validan dentro del diálogo, que también
      // inicia la sesión; al volver con un resultado ya se unió/abrió turno.
      if (u.pinHash != null && u.pinHash!.isNotEmpty) {
        final result = await showPinDialog(context, u);
        if (!mounted) return;
        if (result == null || result == SesionLoginResult.pinIncorrecto) {
          ref.invalidate(usuariosProvider);
        }
        return;
      }

      final result =
          await ref.read(posSessionProvider.notifier).iniciarSesion(u);
      if (!mounted) return;
      _avisarResultado(result);
    } catch (e) {
      if (!mounted) return;
      _snack('No se pudo iniciar sesión: $e', error: true);
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  void _avisarResultado(SesionLoginResult result) {
    switch (result) {
      case SesionLoginResult.soloPcPrincipal:
      case SesionLoginResult.sinTurno:
        _snack(
          'No hay turno abierto. Debe abrirse desde la PC principal.',
          error: true,
        );
        break;
      case SesionLoginResult.pinIncorrecto:
      case SesionLoginResult.nueva:
      case SesionLoginResult.retomada:
        break;
    }
  }

  void _snack(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final usuarios = ref.watch(usuariosProvider);
    final estadoBd = ref.watch(estadoBdProvider);
    final turno = ref.watch(turnoAbiertoProvider).valueOrNull;
    final enTurno = ref.watch(usuariosEnTurnoProvider).valueOrNull ?? <int>{};

    return Center(
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
                turno != null
                    ? 'Se unirá al turno abierto por ${turno.aperturistaNombre}'
                    : puedeAbrirTurno
                        ? 'Seleccione el usuario que abre el turno'
                        : 'El turno debe abrirse desde la PC principal',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            _TurnoBanner(turno: turno),
            const SizedBox(height: 16),
            usuarios.when(
              loading: () => estadoBd == EstadoBd.conectando
                  ? const Center(child: CircularProgressIndicator())
                  : const Center(child: BdNoDisponible()),
              error: (e, _) => const Center(child: BdNoDisponible()),
              data: (lista) => lista.isEmpty
                  ? _sinCajeros()
                  : Column(
                      children: [
                        for (final u in lista) ...[
                          UsuarioCard(
                            usuario: u,
                            selected: u.id == _selectedId,
                            turnoAbierto: enTurno.contains(u.id),
                            onTap: _entrando ? null : () => _login(u),
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
            const Text('No hay usuarios registrados',
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
              label: const Text('Nuevo usuario'),
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
            onPressed: selected == null || _entrando
                ? null
                : () => _login(selected),
            icon: _entrando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.login),
            label: Text(selected == null
                ? 'Iniciar sesión'
                : 'Iniciar sesión como ${selected.nombre}'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Nuevo usuario',
          onPressed: () => showNuevoCajeroDialog(context),
          icon: const Icon(Icons.person_add_alt_1),
        ),
      ],
    );
  }
}

/// Resumen compacto del turno abierto (o aviso si no hay y no se puede abrir).
class _TurnoBanner extends StatelessWidget {
  const _TurnoBanner({required this.turno});

  final TurnoAbierto? turno;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = turno;

    if (t == null) {
      if (puedeAbrirTurno) return const SizedBox.shrink();
      return Card(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No hay turno abierto. Pida que se abra en la PC principal '
                  'para poder unirse.',
                  style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final dentro = t.participantes.where((p) => p.enTurno).length;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.storefront, color: scheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Turno abierto · abrió ${t.aperturistaNombre}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dentro ${dentro == 1 ? 'usuario' : 'usuarios'} dentro · '
                    '${t.ventas} ventas · \$${fmtNumCierre(t.totalVentas)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
