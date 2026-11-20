/// Inicialización de SQLite para el módulo Hostelería.
///
/// Al abrir la app de hostelería se detecta si existe un archivo `.db`
/// junto al ejecutable (en el directorio de documentos de la app).
/// - Si no existe: se crea con todo el esquema de hostelería.
/// - Si existe: se abre tal cual.
///
/// Opcionalmente se puede importar datos desde una base PostgreSQL real
/// (solo para pruebas, no se modifica la BD original).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:control_entradas_salidas/core/data/postgres_service.dart';

import 'hostel_db_backend.dart';
import 'hostel_sqlite_backend.dart';
import 'hostel_sqlite_schema.dart';

/// Nombre del archivo de base de datos local de hostelería.
const _dbFileName = 'lycoris_hosteleria.db';

/// Retorna la ruta completa del archivo `.db` de hostelería.
///
/// Se ubica en el directorio de documentos de la app (junto al ejecutable
/// en la práctica, para escritorio).
Future<String> getHostelDbPath() async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, _dbFileName);
}

/// Abre (o crea) la base de datos SQLite de hostelería y ejecuta el esquema
/// completo. Retorna un [SqliteDbBackend] listo para usar.
///
/// Si `[origenPostgres]` se proporciona, se copian los datos de las tablas
/// de hostelería desde Postgres a SQLite (solo lectura en Postgres, escritura
/// en SQLite). Esto permite tener una base de prueba con datos reales.
Future<SqliteDbBackend> initHosteleriaSqlite({
  PostgresService? origenPostgres,
}) async {
  SqliteDbBackend.initFFI();
  final backend = SqliteDbBackend(await getHostelDbPath());
  await backend.open();

  if (origenPostgres != null) {
    await _importarDesdePostgres(origenPostgres, backend);
  }

  return backend;
}

/// Copia datos de las tablas de hostelería desde PostgreSQL a SQLite.
///
/// Tablas copiadas: tipos_habitacion, habitaciones, hosteleria_huespedes,
/// hosteleria_reservas, hosteleria_reserva_personas, hosteleria_vehiculos.
///
/// Solo lee de Postgres; nunca escribe en la BD original.
Future<void> _importarDesdePostgres(
  PostgresService pg,
  SqliteDbBackend sqlite,
) async {
  final tablas = [
    'tipos_habitacion',
    'habitaciones',
    'hosteleria_huespedes',
    'hosteleria_reservas',
    'hosteleria_reserva_personas',
    'hosteleria_vehiculos',
  ];

  for (final tabla in tablas) {
    try {
      final filas = await pg.executeSql('SELECT * FROM $tabla');
      if (filas.isEmpty) continue;

      // Insertar en lote en SQLite
      for (final fila in filas) {
        // Eliminar claves nulas que SQLite no necesita
        final data = <String, dynamic>{};
        fila.forEach((k, v) {
          if (v != null) data[k] = v;
        });
        await sqlite.insert(tabla, data);
      }
    } catch (e) {
      // Si la tabla no existe en Postgres (esquema antiguo), se ignora.
      // print('[hostel-sqlite] no se pudo importar $tabla: $e');
    }
  }
}
