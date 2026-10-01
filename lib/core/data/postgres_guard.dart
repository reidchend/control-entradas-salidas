import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/db_config.dart';
import '../network/postgres_client.dart';
import 'sql_session.dart';

/// Cuánto se espera por la comprobación antes de darla por fallida.
///
/// El proxy ya tiene un timeout de 60 s en cada consulta, pero para el chequeo
/// de salud eso es demasiado: al usuario le alcanza con saber que no hay
/// servidor, no con esperar un minuto. Con el túnel de por medio, 8 s es
/// holgado para un `SELECT 1`.
const _timeoutChequeo = Duration(seconds: 8);

/// Sesión SQL comprobada contra el servidor.
///
/// [postgresPoolProvider] solo *construye* el objeto de sesión, y eso no abre
/// ninguna conexión: tanto el pool nativo como [HttpSqlSession] quedan listos
/// aunque el servidor esté apagado. Por eso antes la app se reportaba como
/// conectada con la base caída, y el fallo aparecía recién en la primera query,
/// como un error técnico sin contexto.
///
/// Este provider hace la consulta mínima para que [EstadoBd.lista] signifique de
/// verdad "el servidor respondió".
///
/// Va aparte de [postgresPoolProvider] a propósito, y no dentro de
/// `initializePostgres`, por dos razones: los repositorios no deben esperar a
/// esta comprobación para poder trabajar, y meterla en la construcción rompe el
/// seam que los tests usan para apuntar a un servidor local.
final sesionVerificadaProvider = FutureProvider<SqlSession>((ref) async {
  final sesion = await ref.watch(postgresPoolProvider.future);
  try {
    await sesion.execute('SELECT 1').timeout(_timeoutChequeo);
  } on TimeoutException {
    throw const DbNoDisponibleError(
      'El servidor no respondió a tiempo. Revisá que la PC servidor esté '
      'encendida y que el túnel siga corriendo.',
    );
  } catch (e) {
    // Se propaga como DbNoDisponibleError para que la UI lo muestre como
    // "el servidor no está", y no como un fallo de SQL.
    throw DbNoDisponibleError('No se pudo consultar la base de datos: $e');
  }
  return sesion;
});

/// Estado de la conexión a la base, para que la UI pueda diferenciar
/// "no configuré nada todavía" de "está caída".
enum EstadoBd {
  /// Todavía no hay URL, token ni host guardados. La app no tiene a qué
  /// conectarse: hay que abrir Configuración → Base de datos.
  noConfigurada,

  /// Hay configuración y se está abriendo la conexión.
  conectando,

  /// Conectada.
  lista,

  /// Configurada pero la conexión falla: URL/host equivocado, token
  /// incorrecto, servidor caído.
  error,
}

/// Estado de la base, leído de [sesionVerificadaProvider].
///
/// [EstadoBd.lista] solo se alcanza cuando el chequeo de salud respondió, así
/// que por fin distingue "hay sesión" de "hay servidor".
final estadoBdProvider = Provider<EstadoBd>((ref) {
  final verificada = ref.watch(sesionVerificadaProvider);
  return switch (verificada) {
    AsyncData() => EstadoBd.lista,
    AsyncError(:final error) => switch (error) {
        DbNotConfiguredError() => EstadoBd.noConfigurada,
        _ => EstadoBd.error,
      },
    _ => EstadoBd.conectando,
  };
});

/// Detalle del último error de conexión, si lo hubo.
///
/// Lee el provider verificado, no el pool: así el mensaje que ve el usuario es el
/// del chequeo de salud ("el servidor no respondió a tiempo") y no el de la
/// construcción de la sesión, que suele ser más técnico y menos útil.
final errorConexionBdProvider = Provider<Object?>((ref) {
  final verificada = ref.watch(sesionVerificadaProvider);
  return verificada.hasError ? verificada.error : null;
});
