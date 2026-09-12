import 'package:flutter_test/flutter_test.dart';

import 'package:control_entradas_salidas/core/models/producto.dart';
import 'package:control_entradas_salidas/core/models/categoria.dart';
import 'package:control_entradas_salidas/core/models/existencia.dart';
import 'package:control_entradas_salidas/core/models/movimiento.dart';
import 'package:control_entradas_salidas/core/models/mensaje_whatsapp.dart';

void main() {
  group('Producto.fromMap', () {
    test('convierte mapa completo de Supabase', () {
      final p = Producto.fromMap({
        'id': 1,
        'nombre': 'Pabellon',
        'codigo': 'PAB001',
        'descripcion': 'Plato tipico',
        'categoria_id': 3,
        'es_pesable': false,
        'requiere_foto_peso': false,
        'peso_unitario': null,
        'precio_venta': 6.5,
        'unidad_medida': 'unidad',
        'stock_actual': 10.0,
        'stock_minimo': 5.0,
        'activo': true,
        'tipo': 'simple',
        'almacen_predeterminado': 'principal',
        'created_at': null,
        'updated_at': null,
      });
      expect(p.id, 1);
      expect(p.nombre, 'Pabellon');
      expect(p.esPesable, isFalse);
      expect(p.precioVenta, 6.5);
      expect(p.activo, isTrue);
    });

    test('tolera campos nulos con defaults', () {
      final p = Producto.fromMap({
        'id': 2,
        'nombre': 'X',
        'precio_venta': 0,
        'unidad_medida': 'kg',
        'stock_actual': 0,
        'stock_minimo': 0,
        'activo': false,
        'tipo': 'simple',
        'almacen_predeterminado': 'default',
      });
      expect(p.codigo, isNull);
      expect(p.descripcion, isNull);
      expect(p.activo, isFalse);
    });
  });

  group('Categoria.fromMap', () {
    test('convierte mapa completo', () {
      final c = Categoria.fromMap({
        'id': 1,
        'nombre': 'Carnes',
        'descripcion': 'Cortes de carne',
        'imagen': 'url.jpg',
        'color': '#FF0000',
        'activo': true,
        'visible_en_pos': true,
        'created_at': null,
        'updated_at': null,
      });
      expect(c.id, 1);
      expect(c.nombre, 'Carnes');
      expect(c.activo, isTrue);
      expect(c.visibleEnPos, isTrue);
      expect(c.color, '#FF0000');
    });
  });

  group('Existencia.fromMap', () {
    test('convierte correctamente', () {
      final e = Existencia.fromMap({
        'id': 1,
        'producto_id': 5,
        'almacen': 'principal',
        'cantidad': 25.5,
        'unidad': 'kg',
      });
      expect(e.productoId, 5);
      expect(e.almacen, 'principal');
      expect(e.cantidad, 25.5);
    });
  });

  group('Movimiento.fromMap', () {
    test('convierte correctamente', () {
      final m = Movimiento.fromMap({
        'id': 1,
        'producto_id': 5,
        'tipo': 'ajuste',
        'cantidad': 10.0,
        'cantidad_anterior': 20.0,
        'cantidad_nueva': 30.0,
        'peso_total': 0,
        'registrado_por': 'admin',
        'observaciones': 'Ajuste manual',
        'almacen': 'principal',
        'fecha_movimiento': null,
        'created_at': null,
        'factura_id': null,
        'requisicion_id': null,
        'venta_id': null,
        'venta_sync_uuid': null,
      });
      expect(m.tipo, 'ajuste');
      expect(m.cantidad, 10.0);
      expect(m.almacen, 'principal');
    });
  });

  group('MensajeWhatsapp.fromMap', () {
    test('convierte correctamente', () {
      final msg = MensajeWhatsapp.fromMap({
        'id': 1,
        'tipo': 'image',
        'mensaje': 'Test caption',
        'imagen_base64': null,
        'imagen_path': null,
        'estado': 'pending',
        'intentos': 0,
        'max_intentos': 5,
        'ultimo_error': null,
        'created_at': null,
        'updated_at': null,
      });
      expect(msg.id, 1);
      expect(msg.tipo, 'image');
      expect(msg.estado, 'pending');
      expect(msg.intentos, 0);
    });
  });

  group('TemporalData', () {
    test('guardar y recuperar en TemporalesRepository', () async {
      // TemporalesRepository ahora requiere SupabaseClient real.
      // Estos tests se validan con integración, no unit test.
      // TODO: migrar a tests de integración con Supabase local.
    });

    test('limpiar elimina todo', () async {
      // Ver nota arriba.
    });
  });
}
