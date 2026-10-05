/// Error al averiguar la dirección del servidor.
///
/// Va en su propio archivo porque lo lanzan dos responsabilidades distintas —
/// la consulta al Gist y el parseo de lo que publica— y para que esas dos no
/// tengan que importarse entre sí. `descubrimiento_servidor.dart` lo vuelve a
/// exportar, así que los imports existentes siguen valiendo.
class DescubrimientoError implements Exception {
  const DescubrimientoError(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}