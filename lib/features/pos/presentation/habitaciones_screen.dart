import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/pos_models.dart';
import '../data/pos_providers.dart';
import '../data/pos_session.dart';
import 'widgets/habitacion_card.dart';
import 'widgets/pop_in.dart';
import 'widgets/pos_top_bar.dart';

/// Grid de habitaciones con estado Ocupada/Disponible (port de
/// `HabitacionesView`).
class HabitacionesScreen extends ConsumerWidget {
  const HabitacionesScreen({
    super.key,
    required this.sesion,
    required this.onOpenHabitacion,
    required this.onBack,
    required this.onLogout,
  });

  final PosSesionActiva sesion;
  final ValueChanged<Habitacion> onOpenHabitacion;
  final VoidCallback onBack;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habs = ref.watch(habitacionesProvider);
    final ocupadas = ref.watch(habitacionesOcupadasProvider);

    return Scaffold(
      body: Column(
        children: [
          PosTopBar(
            usuario: sesion.usuario,
            titulo: 'Habitaciones',
            onBack: onBack,
            onLogout: onLogout,
          ),
          Expanded(
            child: habs.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (lista) {
                if (lista.isEmpty) return _vacio(context);
                final ocup = ocupadas.value ?? const <int>{};
                return GridView.extent(
                  padding: const EdgeInsets.all(20),
                  maxCrossAxisExtent: 130,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: [
                    for (var i = 0; i < lista.length; i++)
                      PopIn(
                        delay: Duration(milliseconds: (i > 8 ? 8 : i) * 40),
                        child: HabitacionCard(
                          habitacion: lista[i],
                          ocupada: ocup.contains(lista[i].id),
                          onTap: () => onOpenHabitacion(lista[i]),
                        ),
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
            'Vaya a Configuración > Habitaciones para agregar',
            style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
