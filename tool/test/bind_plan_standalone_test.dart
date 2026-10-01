// Ejecuta la logica de `_bindPlan` de lib/core/data/pg_client.dart sin Flutter.
//
// El test del repo (test/pg_client_bind_test.dart) usa `flutter_test`, que no
// corre sin el SDK de Flutter. Este replica el algoritmo tal cual y lo ejecuta
// con `dart test`, para poder verificarlo en una maquina que solo tiene Dart.
//
// Si el algoritmo de _bindPlan cambia, hay que cambiar el de `renumerar`.
// Para correrlo:
//     dart test test/pg_client_bind_standalone_test.dart
//
// Nota: no es el test del repo, solo una red de seguridad para este entorno.

import 'package:test/test.dart';

/// Replica de `_bindPlan` en lib/core/data/pg_client.dart.
///
/// Renumera cada placeholder segun su orden de aparicion y devuelve los
/// parametros en ese mismo orden.
({String sql, List<Object?> params}) renumerar(String sql, List<Object?> bindings) {
  final matches = RegExp(r'\$(\d+)').allMatches(sql);
  if (matches.isEmpty) return (sql: sql, params: const []);

  final buffer = StringBuffer();
  final params = <Object?>[];
  var anterior = 0;
  var siguiente = 1;
  for (final m in matches) {
    buffer
      ..write(sql.substring(anterior, m.start))
      ..write('\$$siguiente');
    params.add(bindings[int.parse(m.group(1)!) - 1]);
    siguiente++;
    anterior = m.end;
  }
  buffer.write(sql.substring(anterior));
  return (sql: buffer.toString(), params: params);
}

/// Cuenta los `%s` que deja `convert_placeholders` en tool/server.py.
///
/// No reconstruye el SQL porque para las pruebas solo hace falta saber cuantos
/// marcadores psycopg va a ver: si no coinciden con la cantidad de parametros,
/// psycopg falla con "the query has N placeholders but M parameters were passed".
int aMarcadoresPyscop(String sql) {
  return RegExp(r'\$(\d+)').allMatches(sql).length;
}

/// Traduce `$n` a `%s` como hace `convert_placeholders` en tool/server.py.
String aMarcadoresPyscopString(String sql) {
  final buffer = StringBuffer();
  var anterior = 0;
  for (final m in RegExp(r'\$(\d+)').allMatches(sql)) {
    buffer
      ..write(sql.substring(anterior, m.start).replaceAll('%', '%%'))
      ..write('%s');
    anterior = m.end;
  }
  buffer.write(sql.substring(anterior).replaceAll('%', '%%'));
  return buffer.toString();
}

void main() {
  group('orden de los parametros', () {
    // Regresion: los filtros del WHERE se registraban antes que los SET, asi
    // que el texto salia `SET col = $3 WHERE id IN ($1, $2)`. Ambos drivers
    // (package:postgres y psycopg) resuelven por posicion en el texto, no por
    // numero, con lo que el valor de la columna caia en el filtro y viceversa.
    test('UPDATE con .eq() no cruza los valores', () {
      // eq('id', 45) se registra primero -> $1; el SET despues -> $2.
      final r = renumerar(
        r'UPDATE movimientos SET factura_id = $2 WHERE id = $1',
        [45, 12],
      );
      expect(r.sql, r'UPDATE movimientos SET factura_id = $1 WHERE id = $2');
      expect(r.params, [12, 45]);
    });

    test('UPDATE con .inFilter() no cruza los valores', () {
      final r = renumerar(
        r'UPDATE movimientos SET factura_id = $3 WHERE id IN ($1, $2)',
        [45, 46, 12],
      );
      expect(r.sql, r'UPDATE movimientos SET factura_id = $1 WHERE id IN ($2, $3)');
      expect(r.params, [12, 45, 46]);
    });

    test('UPDATE con varias columnas y dos condiciones', () {
      final r = renumerar(
        r'UPDATE existencias SET cantidad = $3, observacion = $4 '
        r'WHERE producto_id = $1 AND almacen = $2',
        [7, 'Principal', 10.5, 'recuento'],
      );
      expect(
        r.sql,
        r'UPDATE existencias SET cantidad = $1, observacion = $2 '
        r'WHERE producto_id = $3 AND almacen = $4',
      );
      expect(r.params, [10.5, 'recuento', 7, 'Principal']);
    });

    test('UPDATE sin condiciones', () {
      final r = renumerar(r'UPDATE movimientos SET factura_id = $1', [12]);
      expect(r.sql, r'UPDATE movimientos SET factura_id = $1');
      expect(r.params, [12]);
    });

    test('SELECT mantiene el orden de sus condiciones', () {
      final r = renumerar(
        r'SELECT id FROM movimientos WHERE tipo = $1 AND factura_id = $2',
        ['entrada', 12],
      );
      expect(r.sql, r'SELECT id FROM movimientos WHERE tipo = $1 AND factura_id = $2');
      expect(r.params, ['entrada', 12]);
    });

    test('DELETE con inFilter()', () {
      final r = renumerar(r'DELETE FROM compras_lista WHERE id IN ($1, $2)', [3, 4]);
      expect(r.sql, r'DELETE FROM compras_lista WHERE id IN ($1, $2)');
      expect(r.params, [3, 4]);
    });

    test('los marcadores quedan 1..N, en orden y sin huecos', () {
      final r = renumerar(
        r'UPDATE movimientos SET factura_id = $3 '
        r'WHERE tipo = $1 AND almacen = $2',
        ['entrada', 'Principal', 12],
      );
      final numeros = RegExp(r'\$(\d+)')
          .allMatches(r.sql)
          .map((m) => int.parse(m.group(1)!))
          .toList();
      expect(numeros, [for (var i = 1; i <= numeros.length; i++) i]);
      expect(r.params.length, numeros.length);
    });

    test('SQL sin placeholders queda intacto', () {
      final r = renumerar('SELECT now()', []);
      expect(r.sql, 'SELECT now()');
      expect(r.params, isEmpty);
    });

    test('el texto entre marcadores se conserva intacto', () {
      final r = renumerar(
        r'SELECT a FROM t WHERE b = $2 AND c ILIKE $1 AND d = $3',
        ['x', 'y', 'z'],
      );
      expect(
        r.sql,
        r'SELECT a FROM t WHERE b = $1 AND c ILIKE $2 AND d = $3',
      );
      expect(r.params, ['y', 'x', 'z']);
    });
  });

  group('traduccion al proxy', () {
    test('el SQL renumerado produce tantos %s como parametros', () {
      // Si estas dos cantidades no coinciden, psycopg revienta con
      // "the query has N placeholders but M parameters were passed".
      final r = renumerar(
        r'UPDATE movimientos SET factura_id = $3 WHERE id IN ($1, $2)',
        [45, 46, 12],
      );
      expect(aMarcadoresPyscop(r.sql), r.params.length);
      expect(aMarcadoresPyscopString(r.sql),
          'UPDATE movimientos SET factura_id = %s WHERE id IN (%s, %s)');
    });

    test('un placeholder repetido SI rompe el proxy (por eso se separan)', () {
      // Documenta el limite que motivo el fix de reportes_repository: un `$1`
      // repetido se traduce a dos `%s` con un solo parametro.
      final roto = r'SELECT id FROM productos WHERE nombre ILIKE $1 OR codigo ILIKE $1';
      expect(aMarcadoresPyscop(roto), 2);
      expect(1, isNot(2)); // 1 parametro, 2 marcadores -> psycopg falla
    });
  });
}
