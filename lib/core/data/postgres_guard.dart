import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/db_config.dart';
import '../network/postgres_client.dart';

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

/// Estado de la base leído del [postgresPoolProvider].
///
/// Los repositorios devuelven `null` cuando la base no está, así que sin
/// este provider la UI solo podía mostrar un error genérico que no decía
/// qué hacer.
final estadoBdProvider = Provider<EstadoBd>((ref) {
  final pool = ref.watch(postgresPoolProvider);
  return switch (pool) {
    // `postgresPoolProvider` solo resuelve con una sesión viva: si hay datos,
    // la base está conectada.
    AsyncData() => EstadoBd.lista,
    AsyncError(:final error) => switch (error) {
        DbNotConfiguredError() => EstadoBd.noConfigurada,
        _ => EstadoBd.error,
      },
    _ => EstadoBd.conectando,
  };
});

/// Detalle del último error de conexión, si lo hubo.
final errorConexionBdProvider = Provider<Object?>((ref) {
  final pool = ref.watch(postgresPoolProvider);
  return pool.hasError ? pool.error : null;
});
