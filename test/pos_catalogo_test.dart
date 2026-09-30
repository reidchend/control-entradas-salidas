import 'package:flutter_test/flutter_test.dart';

import 'package:control_entradas_salidas/features/pos/data/pos_comanda_models.dart';

/// Tests del modelo ComandaItem (sin dependencia de base de datos).
void main() {
  group('modelo ComandaItem', () {
    test('round-trip JSON con contornos', () {
      final item = ComandaItem(
        id: 7,
        tipo: 'plato',
        nombre: 'Pabellon',
        precio: 6.5,
        cantidad: 2,
        contornos: const [
          (id: 1, nombre: 'Arroz', cantidad: 1),
          (id: 2, nombre: 'Tajadas', cantidad: 2),
        ],
      );
      final json = item.toJson();
      expect(json['contornos'], ['Arroz', 'Tajadas']);
      expect(json['contorno_ids'], [1, 2]);
      expect(json['contorno_cantidades'], [1, 2]);

      final back = ComandaItem.fromJson(json);
      expect(back.id, 7);
      expect(back.nombre, 'Pabellon');
      expect(back.cantidad, 2);
      expect(back.contornos[1].cantidad, 2);
      expect(back.tieneContornos, isTrue);
      expect(back.subtotal, 13.0);
    });

    test('JSON viejo sin contorno_cantidades: porcion default 1', () {
      final back = ComandaItem.fromJson({
        'id': 3,
        'tipo': 'plato',
        'nombre': 'Pabellon',
        'precio': 6.5,
        'cantidad': 1,
        'contornos': ['Arroz'],
        'contorno_ids': [1],
      });
      expect(back.contornos.single.cantidad, 1);
    });

    test('listFromJson tolera null/vacio', () {
      expect(ComandaItem.listFromJson(null), isEmpty);
      expect(ComandaItem.listFromJson(''), isEmpty);
      expect(ComandaItem.listFromJson('no es json'), isEmpty);
    });
  });
}
