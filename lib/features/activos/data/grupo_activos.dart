import '../../../core/utils/orden_natural.dart';
import 'activo.dart';

/// Conjunto de unidades que comparten exactamente los mismos datos.
///
/// En el inventario cada fila de `activos` es una unidad física, pero diez
/// mesas iguales en el mismo restaurante no necesitan diez tarjetas: se
/// agrupan para mostrar una sola con la cantidad. Solo se agrupa lo que es
/// idéntico (tipo, ubicación, estado, valor, fecha, observaciones y si está
/// activa); si una unidad tiene una nota distinta, queda en su propio grupo
/// para no ocultar esa diferencia.
class GrupoActivos {
  GrupoActivos(List<Activo> unidades)
      : unidades = List.unmodifiable(
          [...unidades]..sort(_compararCodigo),
        );

  /// Unidades del grupo, ordenadas por placa.
  final List<Activo> unidades;

  /// Unidad que se usa como plantilla para clonar datos al agregar.
  Activo get plantilla => unidades.first;

  int get cantidad => unidades.length;

  /// Ids de todas las unidades del grupo, en el orden de [unidades].
  List<int> get ids => [for (final u in unidades) u.id];

  bool get activo => plantilla.activo;

  /// Todas las placas del grupo, en el orden de [unidades].
  List<String> get codigos => [
        for (final u in unidades)
          if ((u.codigo ?? '').trim().isNotEmpty) u.codigo!.trim(),
      ];

  /// Rango compacto de placas para mostrar en la tarjeta.
  String get rangoCodigos {
    final c = codigos;
    if (c.isEmpty) return '';
    if (c.length == 1) return c.first;
    return '${c.first} … ${c.last}';
  }

  /// Ids de las [n] unidades más nuevas (las últimas en crearse).
  ///
  /// Se usan para bajar la cantidad o mover: así se conservan las placas más
  /// viejas y se actúa sobre las recién agregadas.
  List<int> idsUltimas(int n) {
    final ordenadas = [...unidades]..sort((a, b) => b.id.compareTo(a.id));
    return [for (final u in ordenadas.take(n)) u.id];
  }

  /// Placas de las [n] unidades más nuevas, de la más nueva a la más vieja.
  List<String> codigosUltimas(int n) {
    final ordenadas = [...unidades]..sort((a, b) => b.id.compareTo(a.id));
    return [
      for (final u in ordenadas.take(n))
        if ((u.codigo ?? '').trim().isNotEmpty) u.codigo!.trim(),
    ];
  }

  static int _compararCodigo(Activo a, Activo b) {
    final ca = (a.codigo ?? '').trim();
    final cb = (b.codigo ?? '').trim();
    if (ca.isNotEmpty && cb.isNotEmpty) {
      final c = compararNatural(ca, cb);
      if (c != 0) return c;
    }
    return a.id.compareTo(b.id);
  }
}

/// Agrupa unidades idénticas y ordena los grupos por ubicación y nombre.
///
/// El orden es estable respecto a la entrada para los datos que no cambian,
/// así el listado no baila entre recargas.
List<GrupoActivos> agruparActivos(Iterable<Activo> unidades) {
  final porClave = <String, List<Activo>>{};
  for (final a in unidades) {
    porClave.putIfAbsent(_clave(a), () => []).add(a);
  }
  final grupos = [for (final lista in porClave.values) GrupoActivos(lista)];
  grupos.sort((a, b) {
    final ua = _ubicacion(a.plantilla);
    final ub = _ubicacion(b.plantilla);
    if (ua.isEmpty != ub.isEmpty) return ua.isEmpty ? 1 : -1;
    final porUbicacion = compararNatural(ua, ub);
    if (porUbicacion != 0) return porUbicacion;
    final porNombre = compararNatural(a.plantilla.nombre, b.plantilla.nombre);
    if (porNombre != 0) return porNombre;
    return GrupoActivos._compararCodigo(a.plantilla, b.plantilla);
  });
  return grupos;
}

String _clave(Activo a) => [
      a.tipoId ?? 0,
      _ubicacion(a).toLowerCase(),
      a.estado.trim().toLowerCase(),
      a.valor.toStringAsFixed(2),
      (a.fecha ?? '').trim(),
      (a.observaciones ?? '').trim(),
      a.activo ? 1 : 0,
    ].join('\u0001');

String _ubicacion(Activo a) => (a.ubicacion ?? '').trim();
