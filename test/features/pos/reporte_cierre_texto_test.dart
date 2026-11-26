import 'package:flutter_test/flutter_test.dart';

import 'package:control_entradas_salidas/core/models/pos_cierre_models.dart';
import 'package:control_entradas_salidas/features/pos/data/reporte_cierre_texto.dart';

CierreCaja _cierre() => CierreCaja(
      sesionId: 209,
      usuarioId: 5,
      usuarioNombre: 'EMILIO',
      abiertaEn: '2026-10-17T21:02:00',
      cerradaEn: '2026-10-18T06:23:00',
      cajaInicial: 100,
      totalVentas: 427.5,
      cajaFinal: 527.5,
      reporteSimple: ReporteSimple(
        lineas: const [
          LineaVenta(
              nombre: 'Pasta',
              categoria: 'Platos',
              cantidad: 2,
              precioUnitario: 10,
              total: 20),
        ],
        totalGeneral: 20,
        contornos: const [ResumenContorno(nombre: 'Ensalada', cantidad: 1.5)],
        ventasFueraTurno: 3,
        montoFueraTurno: 15.5,
        porUsuario: const [
          ResumenUsuario(
            usuarioId: 5,
            nombre: 'EMILIO',
            esAperturista: true,
            esCerrador: true,
            ventas: 2,
            total: 427.5,
          ),
          ResumenUsuario(usuarioId: 7, nombre: 'ANA', ventas: 1, total: 50),
        ],
      ),
      reporteDetallado: ReporteDetallado(
        desgloses: [
          DesgloseIngrediente(
            ingrediente: 'Harina',
            totalConsumido: 1.25,
            stockFinal: 9.75,
            usos: const [UsoIngrediente(plato: 'Pasta', cantidad: 1.25)],
          ),
        ],
      ),
      syncUuid: 'uuid-test',
      cerradoPorId: 5,
      cerradoPorNombre: 'EMILIO',
    );

void main() {
  group('fmtNumCierre', () {
    test('enteros sin decimales', () {
      expect(fmtNumCierre(2), '2');
      expect(fmtNumCierre(527), '527');
    });

    test('decimales sin ceros finales', () {
      expect(fmtNumCierre(427.5), '427.5');
      expect(fmtNumCierre(1.25), '1.25');
      expect(fmtNumCierre(0.5), '0.5');
    });
  });

  group('duracionCierreTexto', () {
    test('diferencia entre apertura y cierre', () {
      expect(duracionCierreTexto(_cierre()), '9h 21m');
    });
  });

  group('reporteSimpleTexto', () {
    test('incluye apertura, cierre y duración pero ningún monto', () {
      final t = reporteSimpleTexto(_cierre());
      expect(t, contains('CIERRE DE TURNO'));
      expect(t, contains('Apertura:'));
      expect(t, contains('Cierre:'));
      expect(t, contains('Duración: 9h 21m'));
      expect(t, isNot(contains('CAJA')));
      expect(t, isNot(contains('Final:')));
      expect(t, isNot(contains('TOTAL GENERAL')));
      expect(t, isNot(contains(r'$')));
    });

    test('incluye la lista de participantes del turno', () {
      final t = reporteSimpleTexto(_cierre());
      expect(t, contains('PARTICIPANTES'));
      expect(t, isNot(contains('POR USUARIO')));
      expect(t, contains('EMILIO'));
      expect(t, contains('ANA'));
      expect(t, isNot(contains(r'$')));
    });

    test('agrupa por categoría mostrando solo cantidades', () {
      final t = reporteSimpleTexto(_cierre());
      expect(t, contains('PLATOS'));
      expect(t, contains('*Pasta*: 2'));
      expect(t, isNot(contains('Subtotal')));
    });

    test('incluye contornos y aviso de ventas fuera de turno sin montos', () {
      final t = reporteSimpleTexto(_cierre());
      expect(t, contains('CONTORNOS SERVIDOS'));
      expect(t, contains('Ensalada: 1.5'));
      expect(t, contains('VENTAS FUERA DE TURNO'));
      expect(t, contains('3 ventas cobradas'));
      expect(t, isNot(contains('15.5')));
    });
  });

  group('ResumenUsuario', () {
    test('serializa y restaura los campos del desglose', () {
      const u = ResumenUsuario(
        usuarioId: 7,
        nombre: 'ANA',
        esAperturista: true,
        esCerrador: false,
        ventas: 3,
        total: 125.5,
      );
      final back = ResumenUsuario.fromJson(u.toJson());
      expect(back.usuarioId, 7);
      expect(back.nombre, 'ANA');
      expect(back.esAperturista, isTrue);
      expect(back.esCerrador, isFalse);
      expect(back.ventas, 3);
      expect(back.total, 125.5);
    });
  });

  group('reporteDetalladoTexto', () {
    test('contiene desglose por ingrediente con stock y usos, sin montos', () {
      final t = reporteDetalladoTexto(_cierre());
      expect(t, contains('DESGLOSE POR INGREDIENTE'));
      expect(t, contains('Ingrediente: Harina'));
      expect(t, contains('Total consumido: 1.25'));
      expect(t, contains('Stock final:     9.75'));
      expect(t, contains('- Pasta: 1.25'));
      expect(t, isNot(contains('CAJA')));
      expect(t, isNot(contains(r'$')));
    });
  });
}
