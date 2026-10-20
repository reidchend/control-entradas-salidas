import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:control_entradas_salidas/core/ia/gemini_modelos.dart';

Map<String, dynamic> _modelo(String nombre, {bool generateContent = true}) => {
      'name': nombre,
      'supportedGenerationMethods': [
        'countTokens',
        if (generateContent) 'generateContent',
      ],
    };

void main() {
  group('GeminiModelos.disponibles', () {
    test('deja solo Gemini con generateContent y ordena flash, lite, resto',
        () async {
      final cliente = MockClient((req) async {
        expect(req.headers['x-goog-api-key'], 'k-orden');
        return http.Response(
          jsonEncode({
            'models': [
              _modelo('models/gemini-2.5-pro'),
              _modelo('models/gemini-3.8-flash-lite'),
              _modelo('models/gemma-3n-e4b-it'),
              _modelo('models/aqa'),
              _modelo('models/gemini-embedding-001', generateContent: false),
              _modelo('models/gemini-3.8-flash'),
            ],
          }),
          200,
        );
      });

      final lista = await GeminiModelos().disponibles(cliente, 'k-orden');

      expect(lista, [
        'gemini-3.8-flash',
        'gemini-3.8-flash-lite',
        'gemini-2.5-pro',
      ]);
    });

    test('si la API contesta distinto de 200 devuelve lista vacía', () async {
      final cliente = MockClient((_) async => http.Response('no', 403));

      expect(await GeminiModelos().disponibles(cliente, 'k-error'), isEmpty);
    });

    test('si el cuerpo no es JSON devuelve lista vacía', () async {
      final cliente =
          MockClient((_) async => http.Response('<html>', 200, headers: {}));

      expect(await GeminiModelos().disponibles(cliente, 'k-html'), isEmpty);
    });

    test('el listado se cachea por clave y no se pide dos veces', () async {
      var pedidos = 0;
      final cliente = MockClient((_) async {
        pedidos++;
        return http.Response(
          jsonEncode({
            'models': [_modelo('models/gemini-3.5-flash')],
          }),
          200,
        );
      });

      final primera = await GeminiModelos().disponibles(cliente, 'k-cache');
      final segunda = await GeminiModelos().disponibles(cliente, 'k-cache');

      expect(primera, ['gemini-3.5-flash']);
      expect(segunda, primera);
      expect(pedidos, 1);
    });
  });
}
