import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/descubrimiento_servidor.dart';

/// Descubridor de la URL del servidor, compartido.
///
/// Sin `const`: [DescubridorServidor.ultimoFallo] guarda el motivo de la
/// última lectura fallida y tiene que ser el mismo objeto que consulta el
/// panel, o el motivo se pierde entre la lectura y la pantalla.
final descubridorProvider = Provider<DescubridorServidor>(
  (ref) => DescubridorServidor(),
);

/// URL del servidor, resuelta al vuelo.
///
/// `null` mientras consulta o si no se pudo determinar; para el arranque
/// alcanza con leerlo una vez desde el panel o el login.
final urlServidorProvider = FutureProvider<String?>(
  (ref) => ref.watch(descubridorProvider).obtenerUrl(),
);
