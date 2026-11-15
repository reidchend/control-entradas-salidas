import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/pos_providers.dart';

/// Botón de refresco manual de las vistas del POS.
///
/// Fuerza a releer la ocupación de mesas/habitaciones y las comandas abiertas.
/// Es una red de seguridad para cuando el polling automático no alcanzó a
/// reflejar un cambio hecho en otra terminal (red lenta, app en segundo plano,
/// etc.). También sirve para refrescar al instante sin esperar los 5 s.
class BotonActualizarPos extends ConsumerWidget {
  const BotonActualizarPos({super.key, this.mostrarAviso = true});

  /// Muestra un aviso breve para confirmar que se pidió el refresco.
  final bool mostrarAviso;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Actualizar',
      onPressed: () {
        refrescarOcupacionPos(ref);
        if (!mostrarAviso) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Actualizando vista…'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      icon: const Icon(Icons.refresh),
    );
  }
}
