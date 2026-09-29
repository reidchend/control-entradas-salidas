import 'package:control_entradas_salidas/features/pos/presentation/pos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regresión del bloqueo del primer arranque.
///
/// El POS inicializaba el pool ANTES de `runApp`. Sin base configurada eso
/// lanzaba, el error iba a un log invisible y la ventana quedaba en blanco:
/// sin login y sin forma de configurar la conexión.
///
/// Estos tests verifican que la app llega a pintar UI y que ofrece la salida.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> pumpPos(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PosScreen())),
    );
    await tester.pump();
  }

  testWidgets('sin base configurada muestra login, no pantalla en blanco',
      (tester) async {
    await pumpPos(tester);
    await tester.pump(const Duration(milliseconds: 100));

    // La pantalla raíz del POS tiene que existir.
    expect(find.byType(Scaffold), findsWidgets);
    // Y tiene que ofrecer configurar la conexión.
    expect(find.text('Configurar conexión'), findsWidgets);
  });

  testWidgets('el botón de configurar abre el panel de conexión',
      (tester) async {
    await pumpPos(tester);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Configurar conexión').first);
    await tester.pumpAndSettle();

    // El panel de configuración pide host o URL del proxy.
    expect(find.textContaining('Proxy HTTPS'), findsWidgets);
    expect(find.textContaining('TCP directo'), findsWidgets);
  });
}
