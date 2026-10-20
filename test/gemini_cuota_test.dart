import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:control_entradas_salidas/core/ia/gemini_cuota.dart';
import 'package:control_entradas_salidas/core/ia/gemini_vision.dart';

/// Respuesta 200 con un texto corto, del formato que espera GeminiVision.
http.Response _ok(String texto) => http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': texto},
              ],
            },
          },
        ],
      }),
      200,
    );

/// Error 429 con el detalle real de Google (QuotaFailure + RetryInfo).
http.Response _429() => http.Response(
      jsonEncode({
        'error': {
          'code': 429,
          'message': 'You exceeded your current quota.',
          'status': 'RESOURCE_EXHAUSTED',
          'details': [
            {
              '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
              'violations': [
                {
                  'quotaId': 'GenerateRequestsPerDayPerProjectPerModel',
                  'quotaLimit': {'name': 'requests-per-day', 'limit': 250},
                },
              ],
            },
            {
              '@type': 'type.googleapis.com/google.rpc.RetryInfo',
              'retryDelay': '29s',
            },
          ],
        },
      }),
      429,
    );

Uint8List _foto() => Uint8List.fromList([1, 2, 3]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GeminiCuota.diaDeGoogle', () {
    test('agrupa por medianoche hora Pacífico, no por la local', () {
      // 05:00 UTC = 22:00 del día anterior en verano (UTC-7).
      expect(
        GeminiCuota.diaDeGoogle(DateTime.utc(2026, 10, 20, 5)),
        '2026-10-19',
      );
      // 07:00 UTC en verano = medianoche ya en PT: es otro día.
      expect(
        GeminiCuota.diaDeGoogle(DateTime.utc(2026, 10, 20, 7)),
        '2026-10-20',
      );
    });

    test('en invierno usa UTC-8 (horario estándar)', () {
      expect(
        GeminiCuota.diaDeGoogle(DateTime.utc(2026, 1, 15, 7, 59)),
        '2026-01-14',
      );
      expect(
        GeminiCuota.diaDeGoogle(DateTime.utc(2026, 1, 15, 8)),
        '2026-01-15',
      );
    });
  });

  group('GeminiCuota uso', () {
    test('cuenta por modelo y sobrevive a abrir la app de nuevo', () async {
      final cuota = await GeminiCuota.abrir();
      await cuota.registrarUso('gemini-3.8-flash');
      await cuota.registrarUso('gemini-3.8-flash');
      await cuota.registrarUso('gemini-3.5-flash-lite');

      expect(cuota.usadas('gemini-3.8-flash'), 2);
      expect(cuota.usadas('gemini-3.5-flash-lite'), 1);
      expect(cuota.usadas('otro'), 0);
      expect(cuota.ultimoModelo(), 'gemini-3.5-flash-lite');
      expect(cuota.modelosUsados(), ['gemini-3.8-flash', 'gemini-3.5-flash-lite']);

      // Otra instancia = la app se reinició: el conteo sigue ahí.
      final otra = await GeminiCuota.abrir();
      expect(otra.usadas('gemini-3.8-flash'), 2);
    });

    test('el límite aprendido da el avance, y sin límite no inventa saldo',
        () async {
      final cuota = await GeminiCuota.abrir();
      expect(cuota.limite('gemini-3.8-flash'), isNull);
      expect(cuota.avance('gemini-3.8-flash'), isNull);

      await cuota.registrarLimite('gemini-3.8-flash', 250);
      await cuota.registrarUso('gemini-3.8-flash');

      expect(cuota.limite('gemini-3.8-flash'), 250);
      expect(cuota.avance('gemini-3.8-flash'), closeTo(1 / 250, 0.0001));

      // El límite es por modelo: no se filtra a los demás.
      expect(cuota.limite('gemini-2.5-pro'), isNull);
    });

    test('el límite aprendido se persiste entre sesiones', () async {
      final cuota = await GeminiCuota.abrir();
      await cuota.registrarLimite('gemini-3.8-flash', 250);

      final otra = await GeminiCuota.abrir();
      expect(otra.limite('gemini-3.8-flash'), 250);
    });

    test('si el cache guardado es basura, arranca de cero sin romper', () async {
      SharedPreferences.setMockInitialValues({
        'ia_cuota_uso': 'no es json',
        'ia_cuota_limites': '{"m": "tampoco"}',
      });
      final cuota = await GeminiCuota.abrir();

      expect(cuota.usadas('gemini-3.8-flash'), 0);
      expect(cuota.limite('m'), isNull);
      await cuota.registrarUso('gemini-3.8-flash');
      expect(cuota.usadas('gemini-3.8-flash'), 1);
    });

    test('el próximo reinicio es futuro y a menos de un día', () async {
      final cuota = await GeminiCuota.abrir();
      final reinicio = cuota.proximoReinicio();
      final hasta = reinicio.difference(DateTime.now());

      expect(reinicio.isAfter(DateTime.now()), isTrue);
      expect(hasta.inHours, lessThan(25));
    });
  });

  group('GeminiVision con contador de cuota', () {
    test('un 429 entrega el tope y queda aprendido para el indicador',
        () async {
      final cliente = MockClient((req) async {
        if (req.method == 'GET') {
          // El listado de modelos no está disponible para esta clave.
          return http.Response('{"error": {"code": 403}}', 403);
        }
        return _429();
      });
      final cuota = await GeminiCuota.abrir();
      final vision = GeminiVision(cliente: cliente, cuota: cuota);

      IaException? lanzada;
      try {
        await vision.analizarImagen(
          apiKey: 'k-test',
          modelo: 'gemini-3.8-flash',
          prompt: 'p',
          imagen: _foto(),
        );
      } on IaException catch (e) {
        lanzada = e;
      }
      vision.cerrar();

      expect(lanzada, isNotNull);
      expect(lanzada!.limiteCuota, 250);
      expect(lanzada.modeloSaturado, isTrue);
      expect(lanzada.mensaje, contains('250'));
      // El tope quedó guardado aunque la identificación haya fallado.
      expect(cuota.limite('gemini-3.8-flash'), 250);
    });

    test('una identificación exitosa suma al contador', () async {
      final cliente = MockClient((req) async => _ok('{"nombre": "Mesa"}'));
      final cuota = await GeminiCuota.abrir();
      final vision = GeminiVision(cliente: cliente, cuota: cuota);

      final texto = await vision.analizarImagen(
        apiKey: 'k-test',
        modelo: 'gemini-3.8-flash',
        prompt: 'p',
        imagen: _foto(),
      );
      vision.cerrar();

      expect(texto, contains('Mesa'));
      expect(cuota.usadas('gemini-3.8-flash'), 1);
      expect(cuota.ultimoModelo(), 'gemini-3.8-flash');
    });
  });
}
