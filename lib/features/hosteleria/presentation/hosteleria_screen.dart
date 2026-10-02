import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/hosteleria_models.dart';
import '../../../core/models/pos_models.dart';
import '../data/hosteleria_providers.dart';
import 'dialogs/habitacion_detalle_dialog.dart';
import 'dialogs/nueva_reserva_dialog.dart';
import 'widgets/habitacion_grid.dart';
import 'widgets/hostel_top_bar.dart';
import 'widgets/reservas_panel.dart';

/// Pantalla principal de Lycoris Hosteleria: grid de habitaciones con estado y
/// panel de reservas. Orquesta widgets y diálogos (separación por
/// responsabilidad).
class HosteleriaScreen extends ConsumerWidget {
  const HosteleriaScreen({super.key});

  Future<void> _abrirHabitacion(
      BuildContext context, WidgetRef ref, PosHabitacion hab,
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
      ),
    );
    if (nueva == true) {
      ref.invalidate(hostelReservasActivasProvider);
      ref.invalidate(hostelEstadoProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final habs = ref.watch(hostelEstadoProvider);

    return Scaffold(
      body: Column(
        children: [
          HostelTopBar(
            nombreOperador:
                session is Authenticated ? session.nombre : '',
            onSync: () {
              ref.invalidate(hostelReservasActivasProvider);
              ref.invalidate(hostelEstadoProvider);
            },
          ),
          Expanded(
            child: habs.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (estado) {
                final lista = estado.habitaciones;
                if (lista.isEmpty) return _vacio(context);
                final reservaDe = estado.reservasPorHabitacion;
                final activa = estado.reservasActivas;
                return Column(
                  children: [
                    Expanded(
                      child: HabitacionGrid(
                        habitaciones: lista,
                        reservasPorHabitacion: reservaDe,
                        onTap: (hab) => _abrirHabitacion(
                            context, ref, hab,
                            reserva: reservaDe[hab.id]),
                      ),
                    ),
                    ReservasPanel(
                      reservas: activa,
                      onReservar: () => _nuevaReserva(context, ref, lista),
                      onRefresh: () {
                        ref.invalidate(hostelReservasActivasProvider);
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _nuevaReserva(
      BuildContext context, WidgetRef ref, List<PosHabitacion> habitaciones) async {
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