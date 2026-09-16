/// Criterios de filtrado de activos. Todos los campos son opcionales.
class ActivosFiltro {
  const ActivosFiltro({
    this.categoriaId,
    this.categoriaNombre,
    this.grupo,
    this.ubicacion,
    this.modelo,
    this.estado,
  });

  /// Filtro de un único valor de una columna (vista "por valor").
  factory ActivosFiltro.deValor(String columna, String valor) {
    switch (columna) {
      case 'ubicacion':
        return ActivosFiltro(ubicacion: valor);
      case 'grupo':
        return ActivosFiltro(grupo: valor);
      case 'modelo':
        return ActivosFiltro(modelo: valor);
      case 'estado':
        return ActivosFiltro(estado: valor);
    }
    return const ActivosFiltro();
  }

  final int? categoriaId;
  final String? categoriaNombre;
  final String? grupo;
  final String? ubicacion;
  final String? modelo;
  final String? estado;

  bool get vacio =>
      categoriaId == null &&
      (grupo == null || grupo!.isEmpty) &&
      (ubicacion == null || ubicacion!.isEmpty) &&
      (modelo == null || modelo!.isEmpty) &&
      (estado == null || estado!.isEmpty);

  List<String> get descripcion {
    final lista = <String>[];
    if (categoriaNombre != null) lista.add('Categoría: $categoriaNombre');
    if (grupo != null && grupo!.isNotEmpty) lista.add(grupo!);
    if (ubicacion != null && ubicacion!.isNotEmpty) lista.add(ubicacion!);
    if (modelo != null && modelo!.isNotEmpty) lista.add('Modelo: $modelo');
    if (estado != null && estado!.isNotEmpty) lista.add('Estado: $estado');
    return lista;
  }
}