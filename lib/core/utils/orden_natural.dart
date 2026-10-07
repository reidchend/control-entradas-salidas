final RegExp _naturalezaChunks = RegExp(r'\D+|\d+');

/// Compara dos strings como lo haría una persona: los dígitos seguidos se
/// leen como número, no como caracteres (`'Hab 2' < 'Hab 10'`), y la
/// comparación ignora mayúsculas.
///
/// Se usa para ordenar listas de activos por ubicación y por nombre de
/// categoría/tipo, donde el orden alfabético crudo de PostgreSQL (`'Hab 10'`
/// antes que `'Hab 2'`) no coincide con lo que un ser humano espera.
int compararNatural(String a, String b) {
  final ca = _naturalezaChunks.allMatches(a.toLowerCase());
  final cb = _naturalezaChunks.allMatches(b.toLowerCase());
  final la = [for (final m in ca) m.group(0)!];
  final lb = [for (final m in cb) m.group(0)!];
  final n = la.length < lb.length ? la.length : lb.length;

  for (var i = 0; i < n; i++) {
    final xa = la[i];
    final xb = lb[i];
    final na = int.tryParse(xa);
    final nb = int.tryParse(xb);
    if (na != null && nb != null) {
      if (na != nb) return na.compareTo(nb);
      if (xa.length != xb.length) return xa.length.compareTo(xb.length);
    } else if (xa != xb) {
      return xa.compareTo(xb);
    }
  }
  return la.length.compareTo(lb.length);
}
