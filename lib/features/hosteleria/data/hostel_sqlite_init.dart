/// Inicialización de SQLite para el módulo Hostelería.
///
/// Al abrir la app de hostelería se detecta si existe un archivo `.db`
/// junto al ejecutable.
/// - Si no existe: se crea con todo el esquema de hostelería e importa los
///   datos maestros (tipos_habitacion, habitaciones) desde PostgreSQL si
///   está disponible, para que el grid muestre los datos reales sin tocar
///   la BD original.
/// - Si existe: se abre tal cual.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:control_entradas_salidas/core/data/postgres_service.dart';

import 'hostel_db_backend.dart';
import 'hostel_sqlite_backend.dart';
import 'hostel_sqlite_schema.dart';

/// Nombre del archivo de base de datos local de hostelería.
const _dbFileName = 'lycoris_hosteleria.db';

/// Retorna la ruta completa del archivo `.db` de hostelería.
///
/// Se ubica en el mismo directorio del ejecutable para que sea fácil de
/// encontrar y respaldar.
Future<String> getHostelDbPath() async {
  final exe = Platform.script.toFilePath();
  final dir = p.dirname(exe);
  return p.join(dir, _dbFileName);
}

/// Abre (o crea) la base de datos SQLite de hostelería y ejecuta el esquema
/// completo. Retorna un [SqliteDbBackend] listo para usar.
///
/// Si hay una conexión PostgreSQL disponible, importa los datos maestros
/// (tipos_habitacion y habitaciones) desde Postgres a SQLite para que el
/// usuario vea sus habitaciones reales sin tocar la BD original.
Future<SqliteDbBackend> initHosteleriaSqlite({
  PostgresService? origenPostgres,
}) async {
  SqliteDbBackend.initFFI();
  final backend = SqliteDbBackend(await getHostelDbPath());
  await backend.open();

  // Importar datos maestros desde Postgres si está disponible.
  // Esto pobla el SQLite local con las habitaciones reales para que el
  // grid se muestre correctamente, sin modificar la BD original.
  if (origenPostgres != null) {
    await _importarDatosMaestrosDesdePostgres(origenPostgres, backend);
  }

  return backend;
}

/// Copia solo los datos maestros (tipos_habitacion, habitaciones) desde
/// PostgreSQL a SQLite. No toca reservas, huéspedes ni otras tablas.
///
/// Solo lee de Postgres; nunca escribe en la BD original.
Future<void> _importarDatosMaestrosDesdePostgres(
  PostgresService pg,
  SqliteDbBackend sqlite,
) async {
  final tablas = ['tipos_habitacion', 'habitaciones'];

  for (final tabla in tablas) {
    try {
      final filas = await pg.executeSql('SELECT * FROM $tabla');
      if (filas.isEmpty) continue;

      for (final fila in filas) {
        final data = <String, dynamic>{};
        fila.forEach((k, v) {
          if (v != null) data[k] = v;
        });
        await sqlite.insert(tabla, data);
      }
    } catch (e) {
      // Si la tabla no existe en Postgres (esquema antiguo), se ignora.
    }
  }
}
