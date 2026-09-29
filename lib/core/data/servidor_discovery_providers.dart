import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/descubrimiento_servidor.dart';

/// Descubridor de la URL del servidor, compartido.
final descubridorProvider = Provider<DescubridorServidor>(
  (ref) => const DescubridorServidor(),
);

/// URL del servidor, resuelta al vuelo.
///
/// `null` mientras consulta o si no se pudo determinar; para el arranque
/// alcanza con leerlo una vez desde el panel o el login.
final urlServidorProvider = FutureProvider<String?>(
  (ref) => ref.watch(descubridorProvider).obtenerUrl(),
);
