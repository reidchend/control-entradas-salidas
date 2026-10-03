import 'package:flutter_test/flutter_test.dart';

import 'package:control_entradas_salidas/core/utils/fecha_utils.dart';
import 'package:control_entradas_salidas/features/hosteleria/data/hostel_vista.dart';

void main() {
  group('fecha_utils', () {
    test('inicioSemana devuelve el lunes', () {
      final viernes = DateTime(2026, 10, 2);
      expect(inicioSemana(viernes), DateTime(2026, 9, 28));
      expect(finSemana(viernes), DateTime(2026, 10, 4));
    });

    test('inicioSemana con domingo cae en el lunes anterior', () {
      expect(inicioSemana(DateTime(2026, 10, 4)), DateTime(2026, 9, 28));
    });

    test('inicioMes y finMes', () {
      final d = DateTime(2026, 10, 15);
      expect(inicioMes(d), DateTime(2026, 10, 1));
      expect(finMes(d), DateTime(2026, 10, 31));
    });

    test('finMes respeta año bisiesto', () {
      expect(finMes(DateTime(2024, 2, 10)), DateTime(2024, 2, 29));
      expect(finMes(DateTime(2026, 2, 10)), DateTime(2026, 2, 28));
    });

    test('diasEntre ignora la hora', () {
      expect(diasEntre(DateTime(2026, 10, 1, 23), DateTime(2026, 10, 8, 1)), 7);
    });

    test('sumarMeses ancla al día 1', () {
      expect(sumarMeses(DateTime(2026, 10, 31), 1), DateTime(2026, 11, 1));
      expect(sumarMeses(DateTime(2026, 1, 15), -1), DateTime(2025, 12, 1));
    });
  });

  group('rangoDe', () {
    test('semana: lunes a domingo', () {
      final r = rangoDe(HostelVista.semana, DateTime(2026, 10, 2));
      expect(r.desde, DateTime(2026, 9, 28));
      expect(r.hasta, DateTime(2026, 10, 4));
    });

    test('mes: primer a último día', () {
      final r = rangoDe(HostelVista.mes, DateTime(2026, 10, 2));
      expect(r.desde, DateTime(2026, 10, 1));
      expect(r.hasta, DateTime(2026, 10, 31));
    });
  });
}
