import 'dart:convert';
import 'dart:typed_data';

import 'package:control_entradas_salidas/core/data/postgres_service.dart';

/// Datos de una imagen temporal pre-cargada en la vista de Validacion.
class TemporalData {
  final int? id;
  final Uint8List? imagen;
  final String? tipoDocumento;
  final String? nroFactura;
  final String? proveedor;
  final double? monto;
  final DateTime? fecha;
  final DateTime createdAt;

  TemporalData({
    this.id,
    this.imagen,
    this.tipoDocumento,
    this.nroFactura,
    this.proveedor,
    this.monto,
    this.fecha,
    required this.createdAt,
  });
}

/// Repositorio de temporales usando PostgreSQL directo. El polling lo posee el
/// provider (cancela el timer cuando no hay listeners); aquí solo acceso a
/// datos.
class TemporalesRepository {
  TemporalesRepository(this._db);
  final PostgresService _db;

  final _imagenesCache = <int, Uint8List>{};

  /// Lista de temporales SOLO con metadatos (sin `imagen_base64`), para que el
  /// polling de 10s no transfiera ni decodifique el histórico completo.
  Future<List<TemporalData>> getTemporales() async {
    final rows = await _db.client
        .from('pos_temporales')
        .select('id, tipo_documento, nro_factura, proveedor, monto, fecha, creado_en')
        .order('creado_en', ascending: false);
    return rows.map<TemporalData>((r) => TemporalData(
      id: r['id'] as int?,
      tipoDocumento: r['tipo_documento'] as String?,
      nroFactura: r['nro_factura'] as String?,
      proveedor: r['proveedor'] as String?,
      monto: (r['monto'] as num?)?.toDouble(),
      fecha: _parseDate(r['fecha'] as String?),
      createdAt: DateTime.parse(r['creado_en'] as String),
    )).toList();
  }

  /// Imagen de un temporal bajo demanda (con cache en memoria). Se invoca al
  /// renderizar cada miniatura o al "usar" un temporal.
  Future<Uint8List?> getImagenTemporal(int id) async {
    final cache = _imagenesCache[id];
    if (cache != null) return cache;
    final rows = await _db.client
        .from('pos_temporales')
        .select('imagen_base64')
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return null;
    final b64 = rows.first['imagen_base64'] as String?;
    if (b64 == null || b64.isEmpty) return null;
    final bytes = base64Decode(b64);
    _imagenesCache[id] = bytes;
    return bytes;
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  Future<int> guardar({
    required Uint8List imagen,
    String? tipoDocumento,
    String? nroFactura,
    String? proveedor,
    double? monto,
    DateTime? fecha,
  }) async {
    final row = await _db.client.from('pos_temporales').insert({
      'imagen_base64': base64Encode(imagen),
      'tipo_documento': tipoDocumento,
      'nro_factura': nroFactura,
      'proveedor': proveedor,
      'monto': monto,
      'fecha': fecha?.toIso8601String(),
    }).select('id').single();
    return row['id'] as int;
  }

  Future<void> eliminar(int id) async {
    _imagenesCache.remove(id);
    await _db.client.from('pos_temporales').delete().eq('id', id);
  }

  Future<void> limpiar() async {
    _imagenesCache.clear();
    await _db.client.from('pos_temporales').delete().neq('id', 0);
  }
}