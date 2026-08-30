import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_comanda_models.dart';
import '../data/pos_providers.dart';
import '../data/pos_session.dart';
import 'widgets/comandas_activas_panel.dart';
import 'widgets/entry_card.dart';
import 'widgets/pop_in.dart';
import 'widgets/pos_home_header.dart';
import 'widgets/pos_top_bar.dart';

/// Selector de entrada de comandas (port mejorado de `ComandasView`): mesas,
/// habitaciones y ventas con contadores en vivo, acceso a comandas activas y
/// animaciones de entrada escalonadas. El botón de config aparece solo para
/// admins.
class PosHomeScreen extends ConsumerWidget {
  const PosHomeScreen({
    super.key,
    required this.sesion,
    required this.onMesas,
    required this.onHabitaciones,
    required this.onVentas,
    required this.onConfig,
    required this.onLogout,
    required this.onAbrirComanda,
  });

  final PosSesionActiva sesion;
  final VoidCallback onMesas;
  final VoidCallback onHabitaciones;
  final VoidCallback onVentas;
  final VoidCallback onConfig;
  final VoidCallback onLogout;
  final void Function(int? mesaId, int? habitacionId) onAbrirComanda;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final esAdmin = sesion.usuario.esAdmin;

    final mesasOcupadas = ref.watch(mesasOcupadasProvider).valueOrNull?.length ?? 0;
    final habitacionesOcupadas =
        ref.watch(habitacionesOcupadasProvider).valueOrNull?.length ?? 0;
    final ventasSesion = ref.watch(ventasSesionActualProvider);
    final tasa = ref.watch(tasaCambioProvider);
    final comandasActivas =
        ref.watch(comandasActivasProvider).valueOrNull ?? const <ComandaActiva>[];

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.surfaceContainerLowest,
              scheme.surface,
              scheme.surfaceContainerLow,
            ],
          ),
        ),
        child: Column(
          children: [
            PosTopBar(
              usuario: sesion.usuario,
              titulo: 'Lycoris POS',
              onLogout: onLogout,
              actions: [
                if (esAdmin)
                  IconButton(
                    tooltip: 'Configuración',
                    onPressed: onConfig,
                    icon: const Icon(Icons.settings, color: Color(0xFFF57C00)),
                  ),
              ],
            ),
            if (sesion.sesionId == 0)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.science_outlined,
                        size: 18, color: scheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Sesión de desarrollador · sin turno de caja',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final apilado = constraints.maxWidth < 640;
                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      PopIn(
                        child: PosHomeHeader(
                          nombre: sesion.usuario.nombre,
                          tasa: tasa.valueOrNull,
                          cargandoTasa: tasa.isLoading,
                        ),
                      ),
                      SizedBox(height: apilado ? 28 : 36),
                      if (comandasActivas.isNotEmpty) ...[
                        PopIn(
                          delay: const Duration(milliseconds: 120),
                          child: ComandasActivasPanel(
                            comandas: comandasActivas,
                            onAbrirComanda: onAbrirComanda,
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 30,
                        runSpacing: 30,
                        children: [
                          PopIn(
                            delay: const Duration(milliseconds: 180),
                            child: EntryCard(
                              icon: Icons.restaurant,
                              titulo: 'Mesas',
                              subtitulo: 'Área del restaurante',
                              color: const Color(0xFFEF5350),
                              badge: mesasOcupadas > 0
                                  ? '$mesasOcupadas ocupada${mesasOcupadas == 1 ? '' : 's'}'
                                  : null,
                              onTap: onMesas,
                            ),
                          ),
                          PopIn(
                            delay: const Duration(milliseconds: 260),
                            child: EntryCard(
                              icon: Icons.hotel,
                              titulo: 'Habitaciones',
                              subtitulo: 'Servicio a la habitación',
                              color: const Color(0xFF4FC3F7),
                              badge: habitacionesOcupadas > 0
                                  ? '$habitacionesOcupadas ocupada${habitacionesOcupadas == 1 ? '' : 's'}'
                                  : null,
                              onTap: onHabitaciones,
                            ),
                          ),
                          PopIn(
                            delay: const Duration(milliseconds: 340),
                            child: EntryCard(
                              icon: Icons.receipt_long,
                              titulo: 'Ventas',
                              subtitulo: 'Ventas de este turno',
                              color: const Color(0xFF66BB6A),
                              badge: ventasSesion.valueOrNull == null
                                  ? null
                                  : '${ventasSesion.valueOrNull!.cantidad} ventas',
                              valor: ventasSesion.valueOrNull == null
                                  ? null
                                  : '\$${ventasSesion.valueOrNull!.total.toStringAsFixed(2)}',
                              onTap: onVentas,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}