import 'activo_tipo.dart';
import 'activos_categoria.dart';

/// Datos que la IA propone a partir de la foto de un artículo.
///
/// No se guarda nada automáticamente: esto solo precarga el formulario de alta
/// para que el usuario revise y corrija antes de registrar el activo.
class ActivoIdentificado {
  const ActivoIdentificado({
    required this.nombre,
    this.marca = '',
    this.modelo = '',
    this.grupo = '',
    this.categoria = '',
    this.descripcion = '',
    this.valorEstimadoUsd = 0,
    this.confianza = 0,
  });

  final String nombre;
  final String marca;
  final String modelo;
  final String grupo;
  final String categoria;
  final String descripcion;
  final double valorEstimadoUsd;

  /// 0..1 según lo seguro que está el modelo de la identificación.
  final double confianza;

  factory ActivoIdentificado.desdeMap(Map<String, dynamic> m) {
    String texto(String clave) => '${m[clave] ?? ''}'.trim();
    double numero(String clave) {
      final v = m[clave];
      if (v is num) return v.toDouble();
      return double.tryParse('$v'.replaceAll(',', '.')) ?? 0;
    }

    final confianza = numero('confianza');
    return ActivoIdentificado(
      nombre: texto('nombre'),
      marca: texto('marca'),
      modelo: texto('modelo'),
      grupo: texto('grupo'),
      categoria: texto('categoria'),
      descripcion: texto('descripcion'),
      valorEstimadoUsd: numero('valor_estimado_usd'),
      confianza: confianza.clamp(0, 1).toDouble(),
    );
  }

  /// Tipo propuesto para el alta (todavía sin guardar: id 0).
  ActivoTipo aTipo({int? categoriaId}) => ActivoTipo(
        id: 0,
        nombre: nombre.isEmpty ? 'Artículo sin identificar' : nombre,
        grupo: grupo.isEmpty ? null : grupo,
        modelo: modelo.isEmpty ? null : modelo,
        categoriaId: categoriaId,
      );

  /// Categoría del catálogo que mejor coincide con la sugerida por la IA.
  ///
  /// Compara sin mayúsculas ni acentos; si no hay coincidencia exacta acepta
  /// que el nombre de la IA contenga el de la categoría (o al revés).
  int? categoriaIdEn(List<ActivosCategoria> categorias) {
    final buscada = _normalizar(categoria);
    if (buscada.isEmpty) return null;
    for (final c in categorias) {
      if (_normalizar(c.nombre) == buscada) return c.id;
    }
    for (final c in categorias) {
      final nombre = _normalizar(c.nombre);
      if (nombre.isEmpty) continue;
      if (buscada.contains(nombre) || nombre.contains(buscada)) return c.id;
    }
    return null;
  }

  /// Primer tipo del catálogo con el mismo nombre normalizado (sin
  /// mayúsculas, acentos ni espacios repetidos).
  ///
  /// Si hay coincidencia, lo correcto suele ser sumar una unidad a ese tipo en
  /// vez de crear otro: el tipo es la identidad del modelo y cada unidad aporta
  /// su ubicación.
  ActivoTipo? tipoCoincidenteEn(List<ActivoTipo> tipos) {
    final buscado = _normalizar(nombre);
    if (buscado.isEmpty) return null;
    for (final t in tipos) {
      if (_normalizar(t.nombre) == buscado) return t;
    }
    return null;
  }

  /// Texto para el campo Observaciones del formulario.
  String get observaciones {
    final partes = <String>[];
    partes.add('Identificado con IA (confianza ${(confianza * 100).round()}%).');
    if (marca.isNotEmpty) partes.add('Marca: $marca.');
    if (modelo.isNotEmpty) partes.add('Modelo: $modelo.');
    if (descripcion.isNotEmpty) partes.add(descripcion);
    if (valorEstimadoUsd > 0) {
      partes.add(
        'Valor de referencia: USD ${valorEstimadoUsd.toStringAsFixed(2)}.',
      );
    }
    return partes.join(' ');
  }

  static String _normalizar(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp('[áàäâ]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöô]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll('ñ', 'n');
}
