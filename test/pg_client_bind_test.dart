import 'package:flutter_test/flutter_test.dart';

import 'package:control_entradas_salidas/core/data/pg_client.dart';
import 'package:control_entradas_salidas/core/data/sql_session.dart';

/// Sesion que captura el SQL y los parametros sin tocar la base.
class SesionEspia implements SqlSession {
  SesionEspia(this.resultado);

  final SqlResult resultado;
  String? sql;
  List<Object?>? params;
  int llamadas = 0;

  @override
  Future<SqlResult> execute(String sql, {List<Object?>? parameters}) async {
    this.sql = sql;
    this.params = parameters;
    llamadas++;
    return resultado;
  }

  @override
  Future<T> runTx<T>(Future<T> Function(SqlSession tx) action) =>
      action(this);
}

void main() {
  late SesionEspia sesion;
  final ok = SqlResult(rows: const [], affectedRows: 1);

  setUp(() => sesion = SesionEspia(ok));

  group('orden de los parametros', () {
    // Regresion: los placeholders del WHERE se registraban antes que los del
    // SET, asi que el texto salia `SET col = $2 WHERE id = $1`. Ambos drivers
    // (package:postgres y psycopg) resuelven por posicion en el texto, no por
    // numero, con lo que el valor de la columna caia en el filtro y viceversa.
    test('UPDATE con .eq() no cruza los valores', () async {
      await PgClient(sesion)
          .from('movimientos')
          .update({'factura_id': 12})
          .eq('id', 45);

      expect(sesion.sql, 'UPDATE movimientos SET factura_id = $1 WHERE id = $2');
      expect(sesion.params, [12, 45]);
    });

    test('UPDATE con .inFilter() no cruza los valores', () async {
      await PgClient(sesion)
          .from('movimientos')
          .update({'factura_id': 12})
          .inFilter('id', [45, 46]);

      expect(
        sesion.sql,
        'UPDATE movimientos SET factura_id = $1 WHERE id IN ($2, $3)',
      );
      expect(sesion.params, [12, 45, 46]);
    });

    test('UPDATE con varias columnas y dos condiciones', () async {
      await PgClient(sesion)
          .from('existencias')
          .update({'cantidad': 10.5, 'observacion': 'recuento'})
          .eq('producto_id', 7)
          .eq('almacen', 'Principal');

      expect(
        sesion.sql,
        'UPDATE existencias SET cantidad = $1, observacion = $2 '
        'WHERE producto_id = $3 AND almacen = $4',
      );
      expect(sesion.params, [10.5, 'recuento', 7, 'Principal']);
    });

    test('UPDATE sin condiciones', () async {
      await PgClient(sesion).from('movimientos').update({'factura_id': 12});

      expect(sesion.sql, 'UPDATE movimientos SET factura_id = $1');
      expect(sesion.params, [12]);
    });

    test('SELECT mantiene el orden de sus condiciones', () async {
      await PgClient(sesion)
          .from('movimientos')
          .select('id')
          .eq('tipo', 'entrada')
          .eq('factura_id', 12);

      expect(
        sesion.sql,
        'SELECT id FROM movimientos WHERE tipo = $1 AND factura_id = $2',
      );
      expect(sesion.params, ['entrada', 12]);
    });

    test('INSERT con RETURNING ordena sus columnas', () async {
      await PgClient(sesion)
          .from('facturas')
          .insert({'numero_factura': '0001', 'total_neto': 50.0})
          .select('id')
          .single();

      expect(
        sesion.sql,
        'INSERT INTO facturas (numero_factura, total_neto) VALUES ($1, $2) '
        'RETURNING id',
      );
      expect(sesion.params, ['0001', 50.0]);
    });

    test('DELETE con inFilter()', () async {
      await PgClient(sesion).from('compras_lista').delete().inFilter('id', [3, 4]);

      expect(sesion.sql, 'DELETE FROM compras_lista WHERE id IN ($1, $2)');
      expect(sesion.params, [3, 4]);
    });

    test('los marcadores quedan 1..N, en orden y sin huecos', () async {
      await PgClient(sesion)
          .from('movimientos')
          .update({'factura_id': 12})
          .eq('tipo', 'entrada')
          .eq('almacen', 'Principal');

      final numeros = RegExp(r'\$(\d+)')
          .allMatches(sesion.sql!)
          .map((m) => int.parse(m.group(1)!))
          .toList();

      // El driver nativo resuelve los `$n` por indice y el proxy los convierte
      // a `%s` en orden textual: los numeros tienen que salir consecutivos y en
      // el orden en que aparecen. Un hueco o un desfasaje hace que cada valor
      // caiga en la columna de al lado.
      expect(numeros, [for (var i = 1; i <= numeros.length; i++) i]);
      expect(sesion.params!.length, numeros.length);
    });

    });

  group('errores', () {
    test('un UPDATE que falla propaga la excepcion', () async {
      await expectLater(
        PgClient(_SesionQueFalla())
            .from('movimientos')
            .update({'factura_id': 12})
            .eq('id', 45),
        throwsA(isA<StateError>()),
      );
    });

    test('UPDATE con datos vacios no toca la base', () async {
      await PgClient(sesion).from('movimientos').update({}).eq('id', 45);

      expect(sesion.llamadas, 0);
    });
  });
}

class _SesionQueFalla implements SqlSession {
  @override
  Future<SqlResult> execute(String sql, {List<Object?>? parameters}) async {
    throw StateError('boom');
  }

  @override
  Future<T> runTx<T>(Future<T> Function(SqlSession tx) action) =>
      action(this);
}
