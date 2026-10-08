import 'package:flutter_test/flutter_test.dart';

import 'package:control_entradas_salidas/core/data/sql_placeholders.dart';

void main() {
  group('normalizarPlaceholders', () {
    // Regresion: el SQL raw (`executeSql`/`executeCommand`) no pasaba por
    // `_bindPlan`, asi que un `$n` repetido llegaba crudo al proxy, que traduce
    // cada aparicion a `%s` posicional y psycopg reventaba con "the query has N
    // placeholders but M parameters were passed". Reventaba al retomar un turno
    // del POS (`_cerrarAbiertosDeUsuario`).
    test('un \$1 repetido recibe un numero propio y repite su valor', () {
      final r = normalizarPlaceholders(
        'UPDATE t SET a = \$1, b = \$1 WHERE id = \$2',
        [10, 5],
      );
      expect(r.sql, 'UPDATE t SET a = \$1, b = \$2 WHERE id = \$3');
      expect(r.params, [10, 10, 5]);
    });

    test('los placeholders unicos y en orden quedan intactos', () {
      final r = normalizarPlaceholders(
        'SELECT * FROM t WHERE x = \$1 AND y = \$2',
        [1, 2],
      );
      expect(r.sql, 'SELECT * FROM t WHERE x = \$1 AND y = \$2');
      expect(r.params, [1, 2]);
    });

    test('sin placeholders no toca nada', () {
      final r = normalizarPlaceholders('SELECT 1', const []);
      expect(r.sql, 'SELECT 1');
      expect(r.params, isEmpty);
    });

    test('la query real de cerrar sesiones deja los marcadores 1..N', () {
      final r = normalizarPlaceholders(
        'UPDATE pos_sesiones SET cerrada_en = \$1, updated_at = \$1 '
        'WHERE usuario_id = \$2 AND id <> \$3',
        ['now', 3, 188],
      );
      final nums = RegExp(r'\$(\d+)')
          .allMatches(r.sql)
          .map((m) => int.parse(m.group(1)!))
          .toList();
      expect(nums, [for (var i = 1; i <= nums.length; i++) i]);
      expect(r.params, ['now', 'now', 3, 188]);
    });
  });
}