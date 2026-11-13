import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/pos_dispositivo.dart';
import '../../../data/pos_providers.dart';
import '../../../data/pos_turno_models.dart';
import 'turno_abierto_card.dart';
import 'turno_cerrado_card.dart';
import 'turno_detalle_dialog.dart';

/// Vista pública de Turnos del login: turno abierto (para unirse) y turnos
/// cerrados con su detalle.
class TurnosPanel extends ConsumerStatefulWidget {
  const TurnosPanel({super.key, required this.onIrAPersonal});

  /// Lleva a la pestaña Personal para elegir usuario y unirse/abrir turno.
  final VoidCallback onIrAPersonal;

  @override
  ConsumerState<TurnosPanel> createState() => _TurnosPanelState();
}

class _TurnosPanelState extends ConsumerState<TurnosPanel> {
  static const _limite = 30;
  late Future<List<TurnoCerradoResumen>> _cerrados;

  @override
  void initState() {
    super.initState();
    _cerrados = _cargar();
  }

  Future<List<TurnoCerradoResumen>> _cargar() async {
    final turnos =
        await ref.read(posRepoProvider)!.getSesiones(limit: _limite);
    // La lista es de turnos CERRADOS: `getSesiones` devuelve todas las
    // sesiones (incluida la abierta) para el historial de ventas.
    return [
      for (final t in turnos)
        if (t.sesion.cerradaEn != null) t,
    ];
  }

  Future<void> _refrescar() async {
    ref.invalidate(turnoAbiertoProvider);
    ref.invalidate(usuariosEnTurnoProvider);
    final future = _cargar();
    setState(() => _cerrados = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final abierto = ref.watch(turnoAbiertoProvider);

    return RefreshIndicator(
      onRefresh: _refrescar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Turnos',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'Únase al turno abierto o consulte los turnos cerrados.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          abierto.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _ErrorCard(
              mensaje: 'No se pudo cargar el turno abierto: $e',
              onReintentar: () => ref.invalidate(turnoAbiertoProvider),
            ),
            data: (turno) => turno == null
                ? _SinTurnoCard(onIrAPersonal: widget.onIrAPersonal)
                : TurnoAbiertoCard(
                    turno: turno,
                    onUnirse: widget.onIrAPersonal,
                  ),
          ),
          const SizedBox(height: 24),
          Text(
            'Turnos cerrados',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<TurnoCerradoResumen>>(
            future: _cerrados,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return _ErrorCard(
                  mensaje: 'No se pudieron cargar los turnos: ${snapshot.error}',
                  onReintentar: _refrescar,
                );
              }
              final turnos = snapshot.data ?? const <TurnoCerradoResumen>[];
              if (turnos.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.history,
                            size: 32, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 8),
                        Text(
                          'Todavía no hay turnos cerrados.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final t in turnos) ...[
                    TurnoCerradoCard(
                      turno: t,
                      onVer: () => showTurnoDetalleDialog(
                        context,
                        sesionId: t.sesion.id,
                        titulo: 'Turno #${t.sesion.id} · '
                            '${t.usuarioNombre ?? '—'}',
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SinTurnoCard extends StatelessWidget {
  const _SinTurnoCard({required this.onIrAPersonal});

  final VoidCallback onIrAPersonal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.storefront_outlined, size: 36, color: scheme.primary),
            const SizedBox(height: 8),
            const Text(
              'No hay turno abierto',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              puedeAbrirTurno
                  ? 'Seleccione su usuario en Personal para abrir el turno.'
                  : 'El turno debe abrirse desde la PC principal. Cuando esté '
                      'abierto aparecerá aquí para unirse.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (puedeAbrirTurno) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onIrAPersonal,
                icon: const Icon(Icons.login),
                label: const Text('Ir a Personal'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.error_outline, color: scheme.error),
            const SizedBox(height: 8),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            TextButton(
              onPressed: onReintentar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
