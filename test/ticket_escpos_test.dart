import 'package:flutter_test/flutter_test.dart';
import 'package:control_entradas_salidas/features/pos/data/pos_comanda_models.dart'
    show formatearBs;
import 'package:control_entradas_salidas/features/pos/data/ticket_escpos.dart';

void main() {
  const header = TicketHeader(
    nombre: 'TEST REST',
    rif: 'J-12345678-9',
    direccion: 'Av. Principal 123',
    telefono: '0412-5555555',
    size: 'large',
  );

  const items = <TicketItem>[
    (
      cantidad: 2,
      nombre: 'Arepa Reina Pepeada',
      precio: 5.0,
      contornos: ['Queso'],
    ),
    (cantidad: 1, nombre: 'Coca Cola 600ml', precio: 2.5, contornos: []),
  ];

  group('construirTicketEscpos', () {
    test('incluye inicializacion, corte y membrete', () {
      final b = construirTicketEscpos(
        items: items,
        total: 12.5,
        comandaId: 7,
        correlativo: 3,
        tasa: 835.9482,
        cajero: 'Cajero 1',
        mesa: '1 - Terraza',
        header: header,
      );
      expect(b.sublist(0, 2), [0x1b, 0x40]);
      expect(String.fromCharCodes(b), contains('\u001dV\u0000'));
      final s = String.fromCharCodes(b);
      expect(s, contains('TEST REST'));
      expect(s, contains('RIF: J-12345678-9'));
      expect(s, contains('Comanda Nro: 00003'));
      expect(s, contains('Mesa: 1 - Terraza'));
      expect(s, contains('TOTAL Bs: 10.449,35'));
    });

    test('usa doble altura en header large', () {
      final b = construirTicketEscpos(
        items: items,
        header: header,
      );
      final s = String.fromCharCodes(b);
      final idx = s.indexOf('TEST REST');
      expect(b.sublist(idx - 3, idx), [0x1b, 0x21, 0x30]);
    });

    test('marca correccion de comanda', () {
      final b = construirTicketEscpos(
        items: items,
        comandaId: 7,
        correlativo: 9,
        correccionDe: 4,
        header: header,
      );
      expect(
        String.fromCharCodes(b),
        contains('* CORRECCION DE COMANDA 00004 *'),
      );
    });

    test('trunca nombres largos y alinea precio', () {
      final b = construirTicketEscpos(
        items: [
          (cantidad: 1, nombre: 'x' * 40, precio: 12345.67, contornos: []),
        ],
        header: header,
      );
      final s = String.fromCharCodes(b);
      final imprimible = s
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'\x1b..'), '').replaceAll('\u0000', ''));
      final linea = imprimible.firstWhere((l) => l.contains('1x'));
      expect(linea.length, lessThanOrEqualTo(32));
      expect(linea.trim().endsWith(r'$12345.67'), isTrue);
    });

    test('comanda de cocina muestra total en $ y en Bs igual que la copia '
        'cliente', () {
      final b = construirTicketEscpos(
        items: items,
        total: 12.5,
        comandaId: 7,
        correlativo: 3,
        tasa: 835.9482,
        header: header,
        esComandaCocina: true,
      );
      final s = String.fromCharCodes(b);
      expect(s, contains('TOTAL: \$12.50'));
      expect(s, contains('TOTAL Bs: 10.449,35'));
    });
  });

  group('construirTicketPreview', () {
    test('genera lineas de 32 columnas con total alineado', () {
      final lineas = construirTicketPreview(
        items: items,
        total: 12.5,
        comandaId: 7,
        correlativo: 3,
        tasa: 835.9482,
        cajero: 'Cajero 1',
        mesa: '1 - Terraza',
        header: header,
      );
      expect(lineas.first, contains('TEST REST'));
      expect(lineas, contains('Comanda Nro: 00003'));
      expect(lineas, contains('   + Queso'));
      final total = lineas.lastWhere((l) => l.contains('TOTAL:'));
      expect(total.trim(), 'TOTAL: \$12.50');
      for (final l in lineas.where((l) => l.isNotEmpty)) {
        expect(l.length, lessThanOrEqualTo(32));
      }
    });
  });

  group('formatearBs', () {
    test('separa miles y decimales', () {
      expect(formatearBs(10449.35), '10.449,35');
      expect(formatearBs(0), '0,00');
      expect(formatearBs(99.5), '99,50');
    });
  });
}
