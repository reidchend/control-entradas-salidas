import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/hosteleria_models.dart';
import '../../../core/models/pos_models.dart';
import '../data/hostel_session.dart';
import '../data/hostel_timeline_providers.dart';
import '../data/hosteleria_providers.dart';
import 'dialogs/habitacion_detalle_dialog.dart';
import 'dialogs/nueva_reserva_dialog.dart';
import 'hosteleria_config_screen.dart';
import 'widgets/habitacion_grid.dart';
import 'widgets/habitaciones_timeline.dart';
import 'widgets/hostel_rango_nav.dart';
import 'widgets/hostel_top_bar.dart';
import 'widgets/hostel_vista_selector.dart';
import 'widgets/reservas_panel.dart';

/// Pantalla principal de Lycoris Hosteleria: grid de habitaciones con estado y
/// panel de reservas. Orquesta widgets y diálogos (separación por
/// responsabilidad).
class HosteleriaScreen extends ConsumerWidget {
  const HosteleriaScreen({super.key});

  Future<void> _abrirHabitacion(
      BuildContext context, WidgetRef ref, Habitacion hab,
      {HostelReserva? reserva}) async {
    final repo = ref.read(hosteleriaRepoProvider);
    if (repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Base de datos no disponible')),
      );
      return;
    }
    final nueva = await showDialog<bool>(
      context: context,
      builder: (_) => HabitacionDetalleDialog(
        habitacion: hab,
        reserva: reserva,
        repo: repo,
        habitaciones:
            ref.read(hostelEstadoProvider).valueOrNull?.habitaciones ??
                const <Habitacion>[],
      ),
    );
    if (nueva == true) {
      ref.invalidate(hostelReservasActivasProvider);
      ref.invalidate(hostelEstadoProvider);
      ref.invalidate(hostelReservasRangoProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(hostelSessionProvider);
    final habs = ref.watch(hostelEstadoProvider);
    final vista = ref.watch(hostelVistaProvider);
    final ancla = ref.watch(hostelAnclaProvider);

    return Scaffold(
      body: Column(
        children: [
          HostelTopBar(
            nombreOperador: sesion?.nombre ?? '',
            onSync: () {
              ref.invalidate(hostelReservasActivasProvider);
              ref.invalidate(hostelEstadoProvider);
              ref.invalidate(hostelReservasRangoProvider);
            },
            onLogout: () =>
                ref.read(hostelSessionProvider.notifier).cerrarSesion(),
            onConfig: (sesion?.esAdmin ?? false)
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HosteleriaConfigScreen(),
                      ),
                    )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                HostelVistaSelector(
                  vista: vista,
                  onChanged: (v) =>
                      ref.read(hostelVistaProvider.notifier).state = v,
                ),
                const Spacer(),
                if (vista != HostelVista.actual)
                  HostelRangoNav(
                    vista: vista,
                    ancla: ancla,
                    onMover: (d) =>
                        ref.read(hostelAnclaProvider.notifier).state = d,
                  ),
              ],
            ),
          ),
          Expanded(
            child: habs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (estado) {
                final lista = estado.habitaciones;
                if (lista.isEmpty) return _vacio(context);
                if (vista == HostelVista.actual) {
                  return _vistaActual(context, ref, estado);
                }
                return _vistaRango(context, ref, lista, vista, ancla);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaActual(
      BuildContext context, WidgetRef ref, HostelEstado estado) {
    final reservaDe = estado.reservasPorHabitacion;
    return Column(
      children: [
        Expanded(
          child: HabitacionGrid(
            habitaciones: estado.habitaciones,
            reservasPorHabitacion: reservaDe,
            onTap: (hab) =>
                _abrirHabitacion(context, ref, hab, reserva: reservaDe[hab.id]),
          ),
        ),
        ReservasPanel(
          reservas: estado.reservasActivas,
          onReservar: () => _nuevaReserva(context, ref, estado.habitaciones),
          onRefresh: () => ref.invalidate(hostelReservasActivasProvider),
        ),
      ],
    );
  }

  Widget _vistaRango(
    BuildContext context,
    WidgetRef ref,
    List<Habitacion> habitaciones,
    HostelVista vista,
    DateTime ancla,
  ) {
    final rango = rangoDe(vista, ancla);
    final reservas = ref.watch(hostelReservasRangoProvider(rango));
    return reservas.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) => HabitacionesTimeline(
        habitaciones: habitaciones,
        reservas: list,
        desde: rango.desde,
        hasta: rango.hasta,
        anchoDia: vista == HostelVista.semana ? 90 : 38,
        onTap: (hab, r) => _abrirHabitacion(context, ref, hab, reserva: r),
      ),
    );
  }

  Future<void> _nuevaReserva(BuildContext context, WidgetRef ref,
      List<Habitacion> habitaciones) async {
    final repo = ref.read(hosteleriaRepoProvider);
    if (repo == null) return;
    final ok = await showNuevaReservaDialog(
      context,
      repo: repo,
      habitaciones: habitaciones,
    );
    if (ok) {
      ref.invalidate(hostelReservasActivasProvider);
      ref.invalidate(hostelEstadoProvider);
    }
  }

  Widget _vacio(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hotel_outlined, size: 80),
          const SizedBox(height: 20),
          const Text('No hay habitaciones registradas',
              style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            'Registre habitaciones desde el módulo POS (Configuración)',
            style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
