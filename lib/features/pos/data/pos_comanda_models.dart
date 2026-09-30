import 'dart:convert';

/// Comanda abierta enriquecida para el home del POS (etiqueta de
/// mesa/habitación, total e items, con los ids para retomarla).
typedef ComandaActiva = ({
  int comandaId,
  String etiqueta,
  double total,
  int items,
  int? mesaId,
  int? habitacionId,
});

/// Modelo de item de comanda (port del formato de `ComandaPedidoView._build_items_data`).
///
/// Se serializa a JSON para `pos_comandas.items_json` con el mismo formato de
/// la app Flet: `id`, `tipo` (producto|plato|contorno), `nombre`, `precio`,
/// `cantidad` y, si aplica, `contornos` (nombres) + `contorno_ids` +
/// `contorno_cantidades` (porciones por contorno, "doble tostón" = 2).
class ComandaItem {
  ComandaItem({
    required this.id,
    required this.tipo,
    required this.nombre,
    required this.precio,
    required this.cantidad,
    this.contornos = const [],
  });

  final int id;
  final String tipo;
  final String nombre;
  final double precio;
  int cantidad;
  final List<({int? id, String nombre, int cantidad})> contornos;

  bool get tieneContornos => contornos.isNotEmpty;

  double get subtotal => cantidad * precio;

  Map<String, dynamic> toJson() {
    final ids = <int>[];
    final nombres = <String>[];
    final cantidades = <int>[];
    for (final c in contornos) {
      nombres.add(c.nombre);
      if (c.id != null) ids.add(c.id!);
      cantidades.add(c.cantidad);
    }
    return {
      'id': id,
      'tipo': tipo,
      'nombre': nombre,
      'precio': precio,
      'cantidad': cantidad,
      if (contornos.isNotEmpty) 'contornos': nombres,
      if (ids.isNotEmpty) 'contorno_ids': ids,
      if (contornos.isNotEmpty) 'contorno_cantidades': cantidades,
    };
  }

  factory ComandaItem.fromJson(Map<String, dynamic> j) {
    final ids = (j['contorno_ids'] as List?)?.cast<num>().map((n) => n.toInt()).toList();
    final nombres = (j['contornos'] as List?)?.cast<String>() ?? const [];
    final cantidades = (j['contorno_cantidades'] as List?) ?? const [];
    final contornos = <({int? id, String nombre, int cantidad})>[
      for (var i = 0; i < nombres.length; i++)
        (
          id: ids != null && i < ids.length ? ids[i] : null,
          nombre: nombres[i],
          cantidad:
              i < cantidades.length ? (cantidades[i] as num).toInt() : 1,
        ),
    ];
    return ComandaItem(
      id: (j['id'] as num).toInt(),
      tipo: j['tipo'] as String? ?? 'producto',
      nombre: j['nombre'] as String? ?? '?',
      precio: (j['precio'] as num?)?.toDouble() ?? 0,
      cantidad: (j['cantidad'] as num?)?.toInt() ?? 1,
      contornos: contornos,
    );
  }

  static List<ComandaItem> listFromJson(String? json) {
    if (json == null || json.isEmpty) return const [];
    final decoded = _tryDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map<String, dynamic>) ComandaItem.fromJson(e),
    ];
  }

  static String? listToJson(List<ComandaItem> items) {
    if (items.isEmpty) return null;
    try {
      return _encode([
        for (final i in items) i.toJson(),
      ]);
    } catch (_) {
      return null;
    }
  }

  static dynamic _tryDecode(String s) {
    try {
      return const JsonDecoder().convert(s);
    } catch (_) {
      return null;
    }
  }

  static String _encode(dynamic v) => const JsonEncoder().convert(v);
}

/// Formato venezolano 1.234,56 (port de `tasa_cambio.formatear_bs`).
String formatearBs(double monto) {
  final m = monto.abs();
  final entero = m.truncate();
  final decimales = ((m - entero) * 100).round();
  final s = entero.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
  return '${monto < 0 ? '-' : ''}$s,${decimales.toString().padLeft(2, '0')}';
}

/// Tasa con 4 decimales (port de `tasa_cambio.formatear_tasa`), ej: 835,9482.
String formatearTasa(double tasa) {
  final t = tasa.abs();
  final entero = t.truncate();
  final dec = ((t - entero) * 10000).round();
  final s = entero.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
  return '${tasa < 0 ? '-' : ''}$s,${dec.toString().padLeft(4, '0')}';
}
