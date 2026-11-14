import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/pos_models.dart';
import '../data/pos_providers.dart';
import '../data/pos_responsive.dart';
import '../data/pos_session.dart';
import 'dialogs/seleccionar_tipo_cliente_dialog.dart';
import 'widgets/mesa_card.dart';
import 'widgets/pop_in.dart';
import 'widgets/pos_top_bar.dart';

/// Grid de mesas con estado Ocupada/Libre (port de `MesasView`).
class MesasScreen extends ConsumerStatefulWidget {
  const MesasScreen({
    super.key,
    required this.sesion,
    required this.onOpenMesa,
    required this.onBack,
    required this.onLogout,
  });

  final PosSesionActiva sesion;
  /// Callback al tocar una mesa: recibe la mesa, el tipo de cliente
  /// ('particular' | 'huesped') y el texto de habitaciones ('Particular' |
  /// '101, 103' | null).
  final void Function(PosMesa mesa, String? tipoCliente, String? habitaciones)
      onOpenMesa;
  final VoidCallback onBack;
  final VoidCallback onLogout;

  @override
  ConsumerState<MesasScreen> createState() => _MesasScreenState();
}

class _MesasScreenState extends ConsumerState<MesasScreen> {
  @override
  Widget build(BuildContext context) {
    final mesas = ref.watch(mesasProvider);
    final ocupadas = ref.watch(mesasOcupadasProvider);

    return Scaffold(
      body: Column(
        children: [
          PosTopBar(
            usuario: widget.sesion.usuario,
            titulo: 'Mesas',
            onBack: widget.onBack,
            onLogout: widget.onLogout,
          ),
          Expanded(
            child: mesas.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (lista) {
                if (lista.isEmpty) return _vacio(context);
                final ocup = ocupadas.value ?? const <int>{};
                return GridView.extent(
                  padding: EdgeInsets.all(PosResponsive.padding(context)),
                  maxCrossAxisExtent: PosResponsive.maxCrossAxisExtent(context),
                  childAspectRatio: 0.85,
                  crossAxisSpacing: PosResponsive.gridSpacing(context),
                  mainAxisSpacing: PosResponsive.gridSpacing(context),
                  children: [
                    for (var i = 0; i < lista.length; i++)
                      PopIn(
                        delay: Duration(milliseconds: (i > 8 ? 8 : i) * 40),
                        child: MesaCard(
                          mesa: lista[i],
                          ocupada: ocup.contains(lista[i].id),
                          onTap: () async {
                            final resultado =
                                await showSeleccionarTipoClienteDialog(
                              context: context,
                              mesaId: lista[i].id,
                              mesaNumero: lista[i].numero,
                            );
                            if (!mounted) return;
                            if (resultado != null) {
                              final habitacionesTexto =
                                  resultado.esParticular
                                      ? 'Particular'
                                      : resultado.habitaciones;
                              widget.onOpenMesa(
                                lista[i],
                                resultado.tipo,
                                habitacionesTexto,
                              );
                            }
                          },
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
          const Icon(Icons.table_restaurant_outlined, size: 80),
          const SizedBox(height: 20),
          const Text('No hay mesas registradas',
              style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            'Vaya a Configuración > Mesas para agregar',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
