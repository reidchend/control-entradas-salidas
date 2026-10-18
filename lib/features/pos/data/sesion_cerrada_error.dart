/// Se lanza cuando el POS intenta guardar o cobrar una comanda con un turno
/// que ya fue cerrado en BD — p. ej. otra terminal cerró el turno mientras
/// esta pantalla seguía operando con la sesión en memoria.
///
/// Sin esta validación las ventas quedan "huérfanas": se atribuyen a un turno
/// cerrado (salen a nombre de otro cajero) y no entran en ningún cierre.
class SesionCerradaError implements Exception {
  const SesionCerradaError(this.sesionId);

  final int sesionId;

  @override
  String toString() => 'El turno #$sesionId ya fue cerrado desde otra terminal';
}
