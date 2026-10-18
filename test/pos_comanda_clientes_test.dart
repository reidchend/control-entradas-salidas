import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:control_entradas_salidas/features/pos/data/pos_comanda_models.dart';

void main() {
  ComandaItem itemBase({int cuenta = 2, String? nombre}) => ComandaItem(
        id: 10,
        tipo: 'plato',
        nombre: 'Arepa',
        precio: 5.0,
        cantidad: 2,
        cuenta: cuenta,
        cuentaNombre: nombre,
      );

  group('ComandaItem cuenta_nombre', () {
    test('roundtrip JSON conserva el nombre personalizado', () {
      final item = itemBase(nombre: 'Ana');
      final json = item.toJson();
      expect(json['cuenta'], 2);
      expect(json['cuenta_nombre'], 'Ana');
      final back = ComandaItem.fromJson(json);
      expect(back.cuenta, 2);
      expect(back.cuentaNombre, 'Ana');
    });

    test('sin nombre no escribe cuenta_nombre', () {
      final json = itemBase(nombre: null).toJson();
      expect(json.containsKey('cuenta_nombre'), isFalse);
      expect(ComandaItem.fromJson(json).cuentaNombre, isNull);
    });

    test('cliente 1 (cuenta unica) no serializa ni numero ni nombre', () {
      final json = itemBase(cuenta: 1, nombre: 'Ana').toJson();
      expect(json.containsKey('cuenta'), isFalse);
      expect(json.containsKey('cuenta_nombre'), isFalse);
    });

    test('renombrar (campo mutable) se refleja al serializar', () {
      final item = itemBase(nombre: 'Ana');
      item.cuentaNombre = 'Beto';
      expect(item.toJson()['cuenta_nombre'], 'Beto');
      item.cuentaNombre = null;
      expect(item.toJson().containsKey('cuenta_nombre'), isFalse);
    });

    test('copyWith conserva el nombre salvo que se pase otro', () {
      final item = itemBase(nombre: 'Ana');
      expect(item.copyWith(cantidad: 3).cuentaNombre, 'Ana');
      expect(item.copyWith(cuenta: 4).cuentaNombre, 'Ana');
      expect(item.copyWith(cuentaNombre: 'Luis').cuentaNombre, 'Luis');
    });

    test('listFromJson ignora el campo en items viejos sin el nombre', () {
      final items = ComandaItem.listFromJson(jsonEncode([
        {'id': 1, 'tipo': 'producto', 'nombre': 'Refresco', 'precio': 1.5,
         'cantidad': 1, 'cuenta': 3},
      ]));
      expect(items.single.cuenta, 3);
      expect(items.single.cuentaNombre, isNull);
    });
  });

  group('indicesVisibles (filtro por cliente)', () {
    final items = [
      ComandaItem(id: 1, tipo: 'producto', nombre: 'A', precio: 1, cantidad: 1,
          cuenta: 1),
      ComandaItem(id: 2, tipo: 'producto', nombre: 'B', precio: 2, cantidad: 1,
          cuenta: 2),
      ComandaItem(id: 3, tipo: 'producto', nombre: 'C', precio: 3, cantidad: 1,
          cuenta: 1),
      ComandaItem(id: 4, tipo: 'producto', nombre: 'D', precio: 4, cantidad: 1,
          cuenta: 3),
    ];

    test('filtro null devuelve todos los índices', () {
      expect(indicesVisibles(items, null), [0, 1, 2, 3]);
    });

    test('filtro por cliente devuelve solo los suyos con índice real', () {
      // Índices reales sobre _items (no posiciones de vista): clave para que
      // +/−/eliminar operen sobre el item correcto.
      expect(indicesVisibles(items, 1), [0, 2]);
      expect(indicesVisibles(items, 3), [3]);
    });

    test('cliente sin productos devuelve vacío', () {
      expect(indicesVisibles(items, 7), isEmpty);
    });

    test('lista vacía con cualquier filtro devuelve vacío', () {
      expect(indicesVisibles(<ComandaItem>[], null), isEmpty);
      expect(indicesVisibles(<ComandaItem>[], 2), isEmpty);
    });
  });
}
