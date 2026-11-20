/// Esquema SQL de Hostelería para SQLite.
///
/// Se ejecuta al crear la base de datos local (`.db` junto al ejecutable).
/// Incluye las tablas propias de hostelería y las tablas compartidas con el
/// POS (`habitaciones`, `tipos_habitacion`) para que el módulo sea autónomo.
///
/// Los datos de ejemplo están comentados: descomentarlos si se quiere poblar
/// la base de pruebas con contenido real.
final List<String> hosteleriaSqliteSchema = [
  // -------------------------------------------------------------------
  // Tablas compartidas con el POS (solo lectura desde hostelería)
  // -------------------------------------------------------------------
  '''
  CREATE TABLE IF NOT EXISTS tipos_habitacion (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      capacidad INTEGER DEFAULT 1
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS habitaciones (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      numero TEXT NOT NULL,
      piso TEXT,
      tipo TEXT,
      tipo_id INTEGER,
      activo INTEGER DEFAULT 1,
      creado_en TEXT,
      updated_at TEXT,
      estado TEXT DEFAULT 'libre',
      estado_notas TEXT,
      estado_actualizado_en TEXT,
      FOREIGN KEY (tipo_id) REFERENCES tipos_habitacion(id)
  );
  ''',
  // -------------------------------------------------------------------
  // Tablas propias de Hostelería
  // -------------------------------------------------------------------
  '''
  CREATE TABLE IF NOT EXISTS hosteleria_huespedes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      apellido TEXT,
      tipo_documento TEXT,
      numero_documento TEXT,
      fecha_nacimiento TEXT,
      estado_civil TEXT,
      nacionalidad TEXT,
      profesion TEXT,
      procedencia TEXT,
      destino TEXT,
      telefono TEXT,
      correo TEXT,
      notas TEXT,
      cedula TEXT,
      creado_en TEXT,
      updated_at TEXT
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS hosteleria_reservas (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      habitacion_id INTEGER NOT NULL,
      huesped_id INTEGER NOT NULL,
      fecha_inicio TEXT NOT NULL,
      fecha_fin TEXT NOT NULL,
      estado TEXT NOT NULL DEFAULT 'reservada',
      hora_entrada TEXT,
      hora_salida TEXT,
      modalidad TEXT DEFAULT 'noche',
      bloque_horas INTEGER,
      hora_limite TEXT,
      notas TEXT,
      creado_en TEXT,
      updated_at TEXT,
      FOREIGN KEY (habitacion_id) REFERENCES habitaciones(id),
      FOREIGN KEY (huesped_id) REFERENCES hosteleria_huespedes(id)
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS hosteleria_reserva_personas (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reserva_id INTEGER NOT NULL,
      huesped_id INTEGER NOT NULL,
      rol TEXT NOT NULL DEFAULT 'acompanante',
      FOREIGN KEY (reserva_id) REFERENCES hosteleria_reservas(id),
      FOREIGN KEY (huesped_id) REFERENCES hosteleria_huespedes(id)
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS hosteleria_vehiculos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reserva_id INTEGER NOT NULL,
      placa TEXT NOT NULL,
      modelo TEXT,
      FOREIGN KEY (reserva_id) REFERENCES hosteleria_reservas(id)
  );
  ''',
  // -------------------------------------------------------------------
  // Índices útiles
  // -------------------------------------------------------------------
  'CREATE INDEX IF NOT EXISTS idx_hosteleria_reservas_habitacion ON hosteleria_reservas(habitacion_id);',
  'CREATE INDEX IF NOT EXISTS idx_hosteleria_reservas_estado ON hosteleria_reservas(estado);',
  'CREATE INDEX IF NOT EXISTS idx_hosteleria_reservas_fechas ON hosteleria_reservas(fecha_inicio, fecha_fin);',
  'CREATE INDEX IF NOT EXISTS idx_hosteleria_reserva_personas_reserva ON hosteleria_reserva_personas(reserva_id);',
  'CREATE INDEX IF NOT EXISTS idx_hosteleria_vehiculos_reserva ON hosteleria_vehiculos(reserva_id);',
  // -------------------------------------------------------------------
  // Usuarios locales de recepción (para login sin Postgres en modo pruebas)
  // -------------------------------------------------------------------
  '''
  CREATE TABLE IF NOT EXISTS hosteleria_usuarios (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      pin_hash TEXT,
      es_admin INTEGER DEFAULT 0,
      activo INTEGER DEFAULT 1,
      creado_en TEXT
  );
  ''',
  // -------------------------------------------------------------------
  // Datos de ejemplo (descomentar para poblar la base de pruebas)
  // -------------------------------------------------------------------
  /*
  INSERT INTO tipos_habitacion (nombre, capacidad) VALUES
      ('Standard', 2),
      ('Doble', 2),
      ('Suite', 4),
      ('Familiar', 6);

  INSERT INTO habitaciones (numero, piso, tipo, tipo_id, activo, estado)
      VALUES
      ('101', '1', 'Standard', 1, 1, 'libre'),
      ('102', '1', 'Doble', 2, 1, 'libre'),
      ('103', '1', 'Suite', 3, 1, 'libre'),
      ('201', '2', 'Standard', 1, 1, 'libre'),
      ('202', '2', 'Doble', 2, 1, 'libre'),
      ('203', '2', 'Suite', 3, 1, 'aseo');

  INSERT INTO hosteleria_huespedes (nombre, apellido, tipo_documento, numero_documento, telefono, correo)
      VALUES
      ('Juan', 'Pérez', 'cedula', 'V-12345678', '0412-1234567', 'juan@example.com'),
      ('María', 'González', 'cedula', 'V-87654321', '0424-9876543', 'maria@example.com');

  INSERT INTO hosteleria_reservas (habitacion_id, huesped_id, fecha_inicio, fecha_fin, estado, notas)
      VALUES
      (1, 1, '2026-11-20', '2026-11-22', 'reservada', 'Llegada temprana'),
      (2, 2, '2026-11-21', '2026-11-23', 'ocupada', 'Check-in realizado');

  INSERT INTO hosteleria_reserva_personas (reserva_id, huesped_id, rol)
      VALUES
      (1, 1, 'titular'),
      (2, 2, 'titular');

  INSERT INTO hosteleria_vehiculos (reserva_id, placa, modelo)
      VALUES
      (1, 'ABC-1234', 'Toyota Corolla'),
      (2, 'XYZ-5678', 'Chevrolet Aveo');

  INSERT INTO hosteleria_usuarios (nombre, pin_hash, es_admin, activo)
      VALUES
      ('Recepcionista', '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8', 1, 1);
  */
];
