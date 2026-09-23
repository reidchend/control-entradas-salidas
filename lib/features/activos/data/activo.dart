import '../../../core/utils/supabase_cast.dart';

/// Unidad física de un activo del inventario (bienes de la posada).
///
/// En el esquema de "catálogo de tipos + unidades", cada fila es una sola
/// unidad: su identidad/especificación (nombre, grupo, modelo, categoría)
/// vive en su [tipoId] (tabla `activos_tipos`); aquí queda lo individual:
/// ubicación, estado, valor, fecha y observaciones.
class Activo {
  const Activo({
    required this.id,
    this.tipoId,
    this.ubicacion,
    this.estado = 'Activo',
    this.valor = 0,
    this.fecha,
    this.observaciones,
    this.activo = true,
    this.categoriaId,
    this.categoriaNombre,
    this.tipoNombre,
    this.grupo,
    this.modelo,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int? tipoId;
  final String? ubicacion;
  final String estado;
  final double valor;
  final String? fecha;
  final String? observaciones;
  final bool activo;

  /// Campos resueltos por JOIN al catálogo (para display y agrupación).
  final int? categoriaId;
  final String? categoriaNombre;
  final String? tipoNombre;
  final String? grupo;
  final String? modelo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Nombre del tipo al que pertenece (o un placeholder).
  String get nombre {
    final t = (tipoNombre ?? '').trim();
    return t.isEmpty ? 'Sin nombre' : t;
  }

  String get categoria => (categoriaNombre ?? '').trim().isEmpty
      ? 'Sin categoría'
      : categoriaNombre!.trim();

  factory Activo.fromMap(Map<String, dynamic> m) => Activo(
        id: m['id'] as int,
        tipoId: m['tipo_id'] == null
            ? null
            : (m['tipo_id'] as num).toInt(),
        ubicacion: m['ubicacion'] as String?,
        estado: (m['estado'] as String?) ?? 'Activo',
        valor: _toDouble(m['valor']) ?? 0,
        fecha: _fechaTexto(m['fecha']),
        observaciones: m['observaciones'] as String?,
        activo: toBool(m['activo'], fallback: true),
        categoriaId: m['categoria_id'] == null
            ? null
            : (m['categoria_id'] as num).toInt(),
        categoriaNombre: m['categoria_nombre'] as String?,
        tipoNombre: m['tipo_nombre'] as String?,
        grupo: m['grupo'] as String?,
        modelo: m['modelo'] as String?,
        createdAt: _parseDt(m['created_at']),
        updatedAt: _parseDt(m['updated_at']),
      );

  Map<String, dynamic> toMap() => {
        'tipo_id': tipoId,
        'ubicacion': ubicacion,
        'estado': estado,
        'valor': valor,
        'fecha': fecha,
        'observaciones': observaciones,
        'activo': activo ? 1 : 0,
      };

  static String? _fechaTexto(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.length >= 10) return s.substring(0, 10);
    return s;
  }

  static double? _toDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}