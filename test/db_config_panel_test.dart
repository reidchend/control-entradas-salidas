import 'package:control_entradas_salidas/core/data/servidor_discovery_providers.dart';
import 'package:control_entradas_salidas/core/network/descubrimiento_servidor.dart';
import 'package:control_entradas_salidas/features/configuracion/presentation/widgets/db_config_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El flujo configurado es: en el servidor se define `PROXY_SQL_TOKEN` una
/// vez, y en cada equipo el usuario pega ese token. La URL se descubre sola.
///
/// Estos tests fijan esa regla: la URL no se escribe (campo de solo lectura),
/// y existe una salida acotada para escribirla a mano si el Gist no responde.
class _DescubridorFalso extends DescubridorServidor {
  _DescubridorFalso(this._url);

  final String? _url;

  @override
  Future<String?> obtenerUrl({bool forzar = false}) async => _url;

  @override
  Future<String?> urlCacheada() async => _url;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> pumpPanel(WidgetTester tester, {String? url}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (url != null)
            descubridorProvider.overrideWithValue(_DescubridorFalso(url)),
        ],
        child: const MaterialApp(home: Scaffold(body: DbConfigPanel())),
      ),
    );
    // Deja terminar la búsqueda de la URL del arranque.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// `readOnly` no está en `TextFormField`: hay que mirar el `EditableText`
  /// que hay dentro.
  bool esEditable(WidgetTester tester, String etiqueta) {
    final campo = find.widgetWithText(TextFormField, etiqueta);
    expect(campo, findsOneWidget, reason: 'no se encontró el campo "$etiqueta"');
    final interno = find.descendant(of: campo, matching: find.byType(EditableText));
    expect(interno, findsOneWidget);
    return !tester.widget<EditableText>(interno).readOnly;
  }

  testWidgets('la URL no se escribe: se autocompleta y queda bloqueada',
      (tester) async {
    await pumpPanel(tester, url: 'https://api.lycoris.cl');

    expect(esEditable(tester, 'URL del servidor'), isFalse);
    // Y de verdad se llenó sola, sin que nadie escribiera nada.
    expect(find.text('https://api.lycoris.cl'), findsOneWidget);
  });

  testWidgets('el token sí se escribe: es lo único que se escribe a mano',
      (tester) async {
    await pumpPanel(tester, url: 'https://api.lycoris.cl');

    expect(esEditable(tester, 'Token del proxy'), isTrue);
  });

  testWidgets('hay una salida para escribir la URL a mano', (tester) async {
    await pumpPanel(tester, url: 'https://api.lycoris.cl');

    expect(find.text('Escribir la URL a mano'), findsOneWidget);

    await tester.tap(find.text('Escribir la URL a mano'));
    await tester.pump();

    expect(esEditable(tester, 'URL del servidor'), isTrue);
  });

  testWidgets('se puede volver al modo automático', (tester) async {
    await pumpPanel(tester, url: 'https://api.lycoris.cl');

    await tester.tap(find.text('Escribir la URL a mano'));
    await tester.pump();
    expect(find.text('Usar la URL automática'), findsOneWidget);

    await tester.tap(find.text('Usar la URL automática'));
    await tester.pump();

    expect(esEditable(tester, 'URL del servidor'), isFalse);
  });

  testWidgets('si el Gist no responde, el panel ofrece escribirla a mano',
      (tester) async {
    // Sin URL: es el caso "GitHub caído" o "Gist sin crear".
    await pumpPanel(tester, url: null);

    expect(esEditable(tester, 'URL del servidor'), isTrue);
    expect(find.textContaining('No se pudo encontrar la URL'), findsOneWidget);
  });
}
