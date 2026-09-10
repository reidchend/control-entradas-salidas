import 'dart:async';
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

/// Repositorio de temporales usando PostgreSQL directo + polling
/// (reemplaza al Supabase Realtime). Las actualizaciones entre dispositivos
/// se detectan por intervalos de tiempo; no hay suscripciones en vivo.
class TemporalesRepository {
  TemporalesRepository(this._db);
  final PostgresService _db;

  final _controller = StreamController<List<TemporalData>>.broadcast();
  Timer? _timer;

  /// Inicia el polling periódico para detectar cambios en `pos_temporales`.
  Stream<List<TemporalData>> watchTemporales() {
    _startPolling();
    return _controller.stream;
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        await _refrescarSilencioso();
      } catch (_) {
        // Silenciar errores de polling
      }
    });
    _refrescar();
  }

  Future<void> _refrescarSilencioso() async {
    try {
      await _refrescar();
    } catch (_) {}
  }

  Future<void> _refrescar() async {
    final items = await getTemporales();
    if (!_controller.isClosed) {
      _controller.add(items);
    }
  }

  Future<List<TemporalData>> getTemporales() async {
    final rows = await _db.client.from('pos_temporales').select().order('creado_en', ascending: false);
    return rows.map<TemporalData>((r) => TemporalData(
      id: r['id'] as int?,
      imagen: (r['imagen_base64'] as String?) != null
          ? base64Decode(r['imagen_base64'] as String)
          : null,
      tipoDocumento: r['tipo_documento'] as String?,
      nroFactura: r['nro_factura'] as String?,
      proveedor: r['proveedor'] as String?,
      monto: (r['monto'] as num?)?.toDouble(),
      fecha: _parseDate(r['fecha'] as String?),
      createdAt: DateTime.parse(r['creado_en'] as String),
    )).toList();
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
    await _db.client.from('pos_temporales').delete().eq('id', id);
  }

  Future<void> limpiar() async {
    await _db.client.from('pos_temporales').delete().neq('id', 0);
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}