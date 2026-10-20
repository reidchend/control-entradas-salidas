import 'package:flutter_test/flutter_test.dart';

import 'package:control_entradas_salidas/features/activos/data/activo.dart';
import 'package:control_entradas_salidas/features/activos/data/grupo_activos.dart';

Activo _unidad({
  required int id,
  required String codigo,
  int? tipoId = 1,
  String? tipoNombre = 'Mesa',
  String? ubicacion = 'Restaurante',
  String estado = 'Activo',
  double valor = 10,
  String? fecha = '2026-01-01',
  String? observaciones,
  bool activo = true,
}) {
  return Activo(
    id: id,
    tipoId: tipoId,
    tipoNombre: tipoNombre,
    ubicacion: ubicacion,
    estado: estado,
    codigo: codigo,
    valor: valor,
    fecha: fecha,
    observaciones: observaciones,
    activo: activo,
  );
}

void main() {
  group('agruparActivos', () {
    test('junta unidades idénticas y conserva sus placas', () {
      final grupos = agruparActivos([
        _unidad(id: 1, codigo: 'MESA-00001'),
        _unidad(id: 2, codigo: 'MESA-00002'),
        _unidad(id: 3, codigo: 'MESA-00010'),
      ]);

      expect(grupos, hasLength(1));
      expect(grupos.single.cantidad, 3);
      expect(
        grupos.single.codigos,
        ['MESA-00001', 'MESA-00002', 'MESA-00010'],
      );
      expect(grupos.single.rangoCodigos, 'MESA-00001 … MESA-00010');
    });

    test('separa por estado, observaciones y si está activa', () {
      final grupos = agruparActivos([
        _unidad(id: 1, codigo: 'MESA-00001'),
        _unidad(id: 2, codigo: 'MESA-00002', observaciones: 'Rayada'),
        _unidad(id: 3, codigo: 'MESA-00003', estado: 'En reparación'),
        _unidad(id: 4, codigo: 'MESA-00004', activo: false),
      ]);

      expect(grupos, hasLength(4));
      expect(grupos.map((g) => g.cantidad), everyElement(1));
    });

    test('ordena por ubicación y deja Sin ubicación al final', () {
      final grupos = agruparActivos([
        _unidad(id: 1, codigo: 'MESA-00001', ubicacion: null),
        _unidad(id: 2, codigo: 'MESA-00002', ubicacion: 'Bar'),
        _unidad(id: 3, codigo: 'MESA-00003', ubicacion: 'Almacen'),
      ]);

      expect(
        grupos.map((g) => (g.plantilla.ubicacion ?? '').trim()),
        ['Almacen', 'Bar', ''],
      );
    });

    test('idsUltimas devuelve las unidades más nuevas', () {
      final grupo = agruparActivos([
        _unidad(id: 7, codigo: 'MESA-00007'),
        _unidad(id: 9, codigo: 'MESA-00009'),
        _unidad(id: 8, codigo: 'MESA-00008'),
      ]).single;

      expect(grupo.idsUltimas(2), [9, 8]);
      expect(grupo.codigosUltimas(2), ['MESA-00009', 'MESA-00008']);
    });
  });
}
