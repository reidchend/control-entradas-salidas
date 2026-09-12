import '../../../core/utils/supabase_cast.dart';

/// Activo del inventario (bienes muebles/inmuebles de la posada).
class Activo {
  const Activo({
    required this.id,
    required this.nombre,
    this.categoria,
    this.ubicacion,
    this.estado = 'Activo',
    this.valor = 0,
    this.fecha,
    this.observaciones,
    this.grupo,
    this.modelo,
    this.cantidad = 1,
    this.activo = true,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String nombre;
  final String? categoria;
  final String? ubicacion;
  final String estado;
  final double valor;
  final String? fecha;
  final String? observaciones;
  final String? grupo;
  final String? modelo;
  final int cantidad;
  final bool activo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Activo.fromMap(Map<String, dynamic> m) => Activo(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        categoria: m['categoria'] as String?,
        ubicacion: m['ubicacion'] as String?,
        estado: (m['estado'] as String?) ?? 'Activo',
        valor: _toDouble(m['valor']) ?? 0,
        fecha: _fechaTexto(m['fecha']),
        observaciones: m['observaciones'] as String?,
        grupo: m['grupo'] as String?,
        modelo: m['modelo'] as String?,
        cantidad: (m['cantidad'] as num?)?.toInt() ?? 1,
        activo: toBool(m['activo'], fallback: true),
        createdAt: _parseDt(m['created_at']),
        updatedAt: _parseDt(m['updated_at']),
      );

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'categoria': categoria,
        'ubicacion': ubicacion,
        'estado': estado,
        'valor': valor,
        'fecha': fecha,
        'observaciones': observaciones,
        'grupo': grupo,
        'modelo': modelo,
        'cantidad': cantidad,
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