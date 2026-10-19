import '../../../core/data/postgres_service.dart';

/// Motivo frecuente del catálogo `motivos_no_validacion`.
class MotivoNoValidacion {
  const MotivoNoValidacion({required this.id, required this.texto});

  final int id;
  final String texto;
}

/// Catálogo de motivos de no validación + la nota por entrada pendiente.
///
/// La nota vive en `movimientos.motivo_no_validacion` (columna de la
/// migración pendiente `20261019000000_motivos_no_validacion.sql`) y se
/// limpia al validar la entrada (ver `ValidacionRepository._vincularMovimientos`).
class MotivosNoValidacionRepository {
  MotivosNoValidacionRepository(this._db);
  final PostgresService _db;

  /// Motivos predefinidos, ordenados alfabéticamente.
  Future<List<MotivoNoValidacion>> listar() async {
    final rows = await _db.executeSql(
      'SELECT id, texto FROM motivos_no_validacion ORDER BY lower(texto)',
    );
    return [
      for (final r in rows)
        MotivoNoValidacion(
          id: r['id'] as int,
          texto: (r['texto'] as String? ?? '').trim(),
        ),
    ];
  }

  /// Crea un motivo predefinido. Devuelve `false` si ya existe otro con el
  /// mismo texto (sin importar mayúsculas) o si el texto queda vacío.
  Future<bool> crear(String texto) async {
    final t = texto.trim();
    if (t.isEmpty) return false;
    final existe = await _db.executeSql(
      'SELECT 1 FROM motivos_no_validacion WHERE lower(texto) = lower(\$1) '
      'LIMIT 1',
      params: [t],
    );
    if (existe.isNotEmpty) return false;
    await _db.insert('motivos_no_validacion', {'texto': t});
    return true;
  }

  Future<void> eliminar(int id) => _db.deleteById('motivos_no_validacion', id);

  /// Anota (o actualiza) el motivo por el que la entrada aún no se valida.
  /// Un texto vacío equivale a [quitarNota].
  Future<void> guardarNota(int movimientoId, String texto) async {
    final t = texto.trim();
    if (t.isEmpty) return quitarNota(movimientoId);
    await _db.updateById(
      'movimientos',
      movimientoId,
      {'motivo_no_validacion': t},
    );
  }

  /// Quita la nota de la entrada.
  Future<void> quitarNota(int movimientoId) => _db.updateById(
        'movimientos',
        movimientoId,
        {'motivo_no_validacion': null},
      );
}
