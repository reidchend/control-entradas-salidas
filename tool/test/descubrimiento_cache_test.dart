// Verifica la lógica de vigencia de la caché de la URL del servidor, en
// lib/core/network/descubrimiento_servidor.dart, sin depender de Flutter.
//
// El test del repo (test/descubrimiento_servidor_test.dart) usa `flutter_test` y
// `shared_preferences`, que no se pueden ejecutar sin el SDK de Flutter. Este
// replica la decisión "le pregunto al Gist o me quedo con lo que ya sé" y lee la
// constante real del código fuente, así que sigue siendo válido aunque le
// cambien el valor.
//
//     cd tool && dart pub get && dart test
//
// Si cambia el algoritmo de [resolver], hay que cambiar el de acá.

import 'dart:io';

import 'package:test/test.dart';

/// Vigencia declarada en el código de la app, leída del archivo real.
final Duration vigenciaReal = _leerVigencia();

Duration _leerVigencia() {
  final fuente = File('../lib/core/network/descubrimiento_servidor.dart');
  if (!fuente.existsSync()) {
    throw StateError('No se encontró ${fuente.path}. Corré el test desde tool/.');
  }
  final m = RegExp(
          r'_validezCache\s*=\s*Duration\((minutes|hours|seconds):\s*(\d+)\)')
      .firstMatch(fuente.readAsStringSync());
  if (m == null) {
    throw StateError('No se encontró `_validezCache` en el código de la app.');
  }
  final n = int.parse(m.group(2)!);
  return switch (m.group(1)) {
        'minutes' => Duration(minutes: n),
        'hours' => Duration(hours: n),
        _ => Duration(seconds: n),
      };
}

/// Resultado de decidir qué URL usar.
class Resultado {
  const Resultado(this.url, this.consultoGist, this.actualizoCache);

  final String? url;
  final bool consultoGist;
  final bool actualizoCache;
}

/// Replica de la decisión que toma `DescubridorServidor.obtenerUrl`.
///
/// Traduce la misma precedencia: caché vigente → Gist → caché vieja. Lo que se
/// cubre acá es *cuándo* se considera vigente una caché y qué pasa cuando el
/// Gist no contesta, que es donde el síntoma "la app no toma la URL nueva"
/// aparece.
Resultado resolver({
  String? cache,
  int? cacheTs,
  required int ahora,
  String? publicada,
  bool forzar = false,
  Duration? vigencia,
}) {
  final limite = (vigencia ?? vigenciaReal).inMilliseconds;
  final edad = ahora - (cacheTs ?? 0);
  final cacheVigente = cache != null && cache.isNotEmpty && edad < limite;

  if (cacheVigente && !forzar) {
    return Resultado(cache, false, false);
  }
  if (publicada != null && publicada.isNotEmpty) {
    return Resultado(publicada, true, true);
  }
  // El Gist no sirvió: mejor la URL vieja, que existe seguro o no, que nada.
  return Resultado(
    (cache != null && cache.isNotEmpty) ? cache : null,
    true,
    false,
  );
}

void main() {
  const vieja = 'https://tunel-viejo.trycloudflare.com';
  const nueva = 'https://tunel-nuevo.trycloudflare.com';
  final ahora = 1800000000000; //_instante fijo: los tests no dependen del reloj.

  group('vigencia de la caché', () {
    test('la app declara una vigencia corta, de minutos', () {
      // Con el túnel rápido la URL cambia en cada reinicio de la PC servidor.
      // Una vigencia de horas hacía que la app quedara apuntando a un túnel
      // muerto y obligara al usuario a guardar la configuración a mano.
      expect(vigenciaReal.inMinutes, lessThanOrEqualTo(60),
          reason: 'la vigencia no debería pasar de una hora');
      expect(vigenciaReal.inMinutes, greaterThanOrEqualTo(5),
          reason: 'ni tan corta que se pida el Gist en cada pantalla');
    });

    test('una caché más nueva que la vigencia no se vuelve a preguntar', () {
      final r = resolver(
        cache: vieja,
        cacheTs: ahora - vigenciaReal.inMilliseconds + 60000,
        ahora: ahora,
        publicada: nueva,
      );
      expect(r.url, vieja);
      expect(r.consultoGist, isFalse);
    });

    test('una caché más vieja que la vigencia sí se vuelve a preguntar', () {
      final r = resolver(
        cache: vieja,
        cacheTs: ahora - vigenciaReal.inMilliseconds - 60000,
        ahora: ahora,
        publicada: nueva,
      );
      expect(r.url, nueva);
      expect(r.consultoGist, isTrue);
      expect(r.actualizoCache, isTrue);
    });

    test('el límite es exacto: justo en el plazo ya venció', () {
      final r = resolver(
        cache: vieja,
        cacheTs: ahora - vigenciaReal.inMilliseconds,
        ahora: ahora,
        publicada: nueva,
      );
      expect(r.consultoGist, isTrue,
          reason: 'la comparación es estricta: edad < vigencia');
    });
  });

  group('forzar ignora la caché', () {
    test('con forzar pregunta aunque la caché esté vigente', () {
      final r = resolver(
        cache: vieja,
        cacheTs: ahora,
        ahora: ahora,
        publicada: nueva,
        forzar: true,
      );
      expect(r.url, nueva);
      expect(r.consultoGist, isTrue);
    });

    test('sin forzar, con la caché al día, no toca la red', () {
      // Este es el ahorro que hace posible forzar en cada arranque: el resto de
      // las consultas de la sesión siguen sirviéndose de la caché.
      final r = resolver(
        cache: vieja,
        cacheTs: ahora,
        ahora: ahora,
        publicada: nueva,
      );
      expect(r.consultoGist, isFalse);
    });
  });

  group('el Gist no responde', () {
    test('con caché a mano se cae a ella, sin error', () {
      final r = resolver(
        cache: vieja,
        cacheTs: ahora - vigenciaReal.inMilliseconds - 60000,
        ahora: ahora,
      );
      expect(r.url, vieja, reason: 'forzar nunca debe dejar a la app sin URL');
      expect(r.actualizoCache, isFalse,
          reason: 'no hay qué guardar: la caché queda con su fecha vieja');
    });

    test('sin caché a mano devuelve null', () {
      final r = resolver(ahora: ahora);
      expect(r.url, isNull);
    });

    test('una caché vacía cuenta como no tener nada', () {
      final r = resolver(cache: '', cacheTs: ahora, ahora: ahora);
      expect(r.consultoGist, isTrue);
      expect(r.url, isNull);
    });
  });

  test('la URL publicada se guarda con la fecha de ahora', () {
    // Si la caché se guardara con la fecha que tenía antes, la vigencia se
    // reiniciaría sola y la app nunca volvería a expirarla.
    final r = resolver(
      cache: vieja,
      cacheTs: ahora - vigenciaReal.inMilliseconds - 60000,
      ahora: ahora,
      publicada: nueva,
    );
    expect(r.actualizoCache, isTrue);
    // Simula la escritura: la nueva caché nace ahora, o sea vigente.
    final siguiente = resolver(
      cache: r.url,
      cacheTs: ahora,
      ahora: ahora,
      publicada: 'https://otra.trycloudflare.com',
    );
    expect(siguiente.url, nueva);
    expect(siguiente.consultoGist, isFalse);
  });
}