"""
Réplica local SQLite para trabajo offline.
Almacena una copia de los datos de Supabase para acceso offline.
"""
from datetime import datetime
from typing import Optional, List, Dict, Any
from usr.database.conn import get_local_conn
from config.config import get_settings

from usr.database.sync_queue import (
    SyncQueue,
)

def init_local_db():
    """Inicializa la base de datos local con todas las tablas.
    Usa los mismos nombres de tabla que SQLAlchemy para compatibilidad."""
    conn = get_local_conn()
    cursor = conn.cursor()
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS categorias (
            id INTEGER PRIMARY KEY,
            nombre TEXT NOT NULL,
            descripcion TEXT,
            imagen TEXT,
            color TEXT DEFAULT '#2196F3',
            activo INTEGER DEFAULT 1,
            created_at TEXT,
            updated_at TEXT
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS proveedores (
            id INTEGER PRIMARY KEY,
            nombre TEXT NOT NULL UNIQUE,
            rif TEXT,
            telefono TEXT,
            email TEXT,
            direccion TEXT,
            contacto TEXT,
            observaciones TEXT,
            estado TEXT DEFAULT 'Activo',
            created_at TEXT
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS productos (
            id INTEGER PRIMARY KEY,
            nombre TEXT NOT NULL,
            codigo TEXT UNIQUE,
            descripcion TEXT,
            categoria_id INTEGER,
            es_pesable INTEGER DEFAULT 0,
            requiere_foto_peso INTEGER DEFAULT 0,
            peso_unitario REAL,
            unidad_medida TEXT DEFAULT 'unidad',
            stock_actual REAL DEFAULT 0,
            stock_minimo REAL DEFAULT 0,
            activo INTEGER DEFAULT 1,
            tipo TEXT,
            created_at TEXT,
            updated_at TEXT,
            almacen_predeterminado TEXT DEFAULT 'principal'
        )
    """)
    
    # Migración: agregar columna tipo a productos si no existe
    try:
        cursor.execute("ALTER TABLE productos ADD COLUMN tipo TEXT")
    except Exception:
        pass  # Ya existe
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS existencias (
            id INTEGER PRIMARY KEY,
            producto_id INTEGER NOT NULL,
            almacen TEXT NOT NULL,
            cantidad REAL DEFAULT 0,
            unidad TEXT DEFAULT 'unidad'
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS movimientos (
            id INTEGER PRIMARY KEY,
            producto_id INTEGER NOT NULL,
            factura_id INTEGER,
            tipo TEXT NOT NULL,
            cantidad REAL NOT NULL,
            cantidad_anterior REAL DEFAULT 0,
            cantidad_nueva REAL DEFAULT 0,
            peso_total REAL DEFAULT 0,
            peso_registrado REAL,
            foto_peso_url TEXT,
            registrado_por TEXT,
            observaciones TEXT,
            almacen TEXT,
            fecha_movimiento TEXT,
            created_at TEXT,
            device_id TEXT,
            sincronizado INTEGER DEFAULT 0
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS facturas (
            id INTEGER PRIMARY KEY,
            numero_factura TEXT NOT NULL UNIQUE,
            proveedor TEXT,
            fecha_factura TEXT NOT NULL,
            fecha_recepcion TEXT,
            total_bruto REAL DEFAULT 0,
            total_impuestos REAL DEFAULT 0,
            total_neto REAL DEFAULT 0,
            estado TEXT DEFAULT 'Pendiente',
            observaciones TEXT,
            validada_por TEXT,
            fecha_validacion TEXT,
            created_at TEXT,
            updated_at TEXT
        )
    """)
    
    # Migración: agregar columna tipo_documento a facturas si no existe
    try:
        cursor.execute("ALTER TABLE facturas ADD COLUMN tipo_documento TEXT DEFAULT 'Factura'")
    except Exception:
        pass  # Ya existe
    
    # Tabla de pagos de facturas
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS factura_pagos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            factura_id INTEGER NOT NULL,
            tipo_pago TEXT NOT NULL,
            monto REAL NOT NULL,
            referencia TEXT,
            tasa_cambio REAL,
            fecha_pago TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (factura_id) REFERENCES facturas(id) ON DELETE CASCADE
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS requisiciones (
            id INTEGER PRIMARY KEY,
            numero TEXT NOT NULL UNIQUE,
            numero_secuencial INTEGER NOT NULL,
            origen TEXT NOT NULL,
            destino TEXT NOT NULL,
            estado TEXT DEFAULT 'pendiente',
            observaciones TEXT,
            creada_por TEXT,
            procesada_por TEXT,
            fecha_procesamiento TEXT,
            fecha_creacion TEXT,
            actualizada TEXT
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS requisicion_detalles (
            id INTEGER PRIMARY KEY,
            requisicion_id INTEGER NOT NULL,
            producto_id INTEGER,
            ingrediente TEXT NOT NULL,
            cantidad REAL NOT NULL,
            unidad TEXT DEFAULT 'unidad',
            cantidad_surtida REAL DEFAULT 0
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS sync_metadata (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TEXT
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS pending_operations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            operation TEXT NOT NULL,
            record_id INTEGER,
            data TEXT,
            created_at TEXT NOT NULL,
            retries INTEGER DEFAULT 0
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS dispositivo_usuario (
            id          INTEGER PRIMARY KEY,
            nombre      TEXT    NOT NULL,
            pin_hash    TEXT,
            configurado_en TEXT NOT NULL
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS compras_lista (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            producto_id INTEGER NOT NULL,
            created_at TEXT
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS whatsapp_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tipo TEXT NOT NULL,
            mensaje TEXT,
            imagen_base64 TEXT,
            imagen_path TEXT,
            estado TEXT DEFAULT 'pending',
            intentos INTEGER DEFAULT 0,
            max_intentos INTEGER DEFAULT 10,
            ultimo_error TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS recetas (
            id INTEGER PRIMARY KEY,
            nombre TEXT NOT NULL,
            tipo TEXT NOT NULL,
            producto_base_id INTEGER,
            producto_final_id INTEGER,
            cantidad_producida REAL DEFAULT 1,
            activo INTEGER DEFAULT 1,
            created_at TEXT,
            updated_at TEXT
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS receta_componentes (
            id INTEGER PRIMARY KEY,
            receta_id INTEGER NOT NULL,
            producto_id INTEGER NOT NULL,
            cantidad REAL NOT NULL,
            unidad TEXT DEFAULT 'unidad',
            tipo_componente TEXT NOT NULL
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS producciones (
            id INTEGER PRIMARY KEY,
            receta_id INTEGER NOT NULL,
            cantidad REAL NOT NULL,
            estado TEXT DEFAULT 'completado',
            usuario TEXT,
            observaciones TEXT,
            fecha_produccion TEXT,
            created_at TEXT
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS produccion_detalles (
            id INTEGER PRIMARY KEY,
            produccion_id INTEGER NOT NULL,
            producto_id INTEGER NOT NULL,
            tipo TEXT NOT NULL,
            cantidad REAL NOT NULL,
            unidad TEXT DEFAULT 'unidad',
            movimiento_id INTEGER
        )
    """)
    
    conn.commit()
    conn.close()

def _migrate_old_tables(conn):
    """Migra datos de tablas old (local_*) a tablas nuevas si existen datos en old."""
    cursor = conn.cursor()
    
    tables_map = [
        ('local_categorias', 'categorias'),
        ('local_productos', 'productos'),
        ('local_existencias', 'existencias'),
        ('local_movimientos', 'movimientos'),
        ('local_facturas', 'facturas'),
        ('local_requisiciones', 'requisiciones'),
    ]
    
    for old_table, new_table in tables_map:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {old_table}")
            old_count = cursor.fetchone()[0]
            cursor.execute(f"SELECT COUNT(*) FROM {new_table}")
            new_count = cursor.fetchone()[0]
            
            if old_count > 0 and new_count == 0:
                cursor.execute(f"INSERT OR IGNORE INTO {new_table} SELECT * FROM {old_table}")
                print(f"[MIGRATE] {old_table} -> {new_table}: {cursor.rowcount} registros")
        except Exception as e:
            pass
    
    conn.commit()

class LocalReplica:
    """Clase para manejar la réplica local de datos."""
    
    @staticmethod
    def create_tables():
        """Crea todas las tablas locales."""
        init_local_db()
    
    # ==================== CATEGORÍAS ====================
    
    @staticmethod
    def clear_categorias() -> None:
        """Elimina todas las categorías de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM categorias")
        conn.commit()
        conn.close()
    
    @staticmethod
    def save_categorias(categorias: List[Dict]) -> None:
        """Guarda categorías en la base de datos local (upsert, no borra)."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        for cat in categorias:
            cursor.execute("""
                INSERT OR REPLACE INTO categorias 
                (id, nombre, descripcion, imagen, color, activo, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                cat.get('id'), cat.get('nombre'), cat.get('descripcion'),
                cat.get('imagen'), cat.get('color', '#2196F3'),
                1 if cat.get('activo', True) else 0,
                cat.get('created_at'), cat.get('updated_at')
            ))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_categorias() -> List[Dict]:
        """Obtiene todas las categorías de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM categorias WHERE activo = 1 ORDER BY nombre")
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    # ==================== PROVEEDORES ====================
    
    @staticmethod
    def save_proveedores(proveedores: List[Dict]) -> None:
        """Guarda proveedores en la base de datos local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        for prov in proveedores:
            cursor.execute("""
                INSERT OR REPLACE INTO proveedores 
                (id, nombre, rif, telefono, email, direccion, contacto, observaciones, estado, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                prov.get('id'), prov.get('nombre'), prov.get('rif'),
                prov.get('telefono'), prov.get('email'), prov.get('direccion'),
                prov.get('contacto'), prov.get('observaciones'),
                prov.get('estado', 'Activo'), prov.get('created_at')
            ))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_proveedores(estado: str = None) -> List[Dict]:
        """Obtiene todos los proveedores de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        if estado:
            cursor.execute("SELECT * FROM proveedores WHERE estado = ? ORDER BY nombre", (estado,))
        else:
            cursor.execute("SELECT * FROM proveedores ORDER BY nombre")
        
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    @staticmethod
    def get_proveedor_by_nombre(nombre: str) -> Dict | None:
        """Obtiene un proveedor por su nombre."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM proveedores WHERE nombre = ?", (nombre,))
        row = cursor.fetchone()
        conn.close()
        
        return dict(row) if row else None
    
    @staticmethod
    def migrate_proveedores_from_facturas() -> int:
        """Migra proveedores únicos de facturas a la tabla de proveedores."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("SELECT DISTINCT proveedor FROM facturas WHERE proveedor IS NOT NULL AND proveedor != 'Varios'")
        rows = cursor.fetchall()
        
        count = 0
        for row in rows:
            nombre = row[0]
            try:
                cursor.execute("INSERT OR IGNORE INTO proveedores (nombre, estado) VALUES (?, 'Activo')", (nombre,))
                count += 1
            except:
                pass
        
        conn.commit()
        conn.close()
        return count
    
    # ==================== PRODUCTOS ====================
    
    @staticmethod
    def clear_productos() -> None:
        """Elimina todos los productos de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM productos")
        conn.commit()
        conn.close()
    
    @staticmethod
    def save_productos(productos: List[Dict]) -> None:
        """Guarda productos en la base de datos local (upsert, no borra)."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        for prod in productos:
            cursor.execute("""
                INSERT OR REPLACE INTO productos 
                (id, nombre, codigo, descripcion, categoria_id, es_pesable, 
                 requiere_foto_peso, peso_unitario, unidad_medida, stock_actual, 
                 stock_minimo, activo, tipo, created_at, updated_at, almacen_predeterminado)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                prod.get('id'), prod.get('nombre'), prod.get('codigo'),
                prod.get('descripcion'), prod.get('categoria_id'),
                1 if prod.get('es_pesable') else 0,
                1 if prod.get('requiere_foto_peso') else 0,
                prod.get('peso_unitario'), prod.get('unidad_medida', 'unidad'),
                prod.get('stock_actual', 0), prod.get('stock_minimo', 0),
                1 if prod.get('activo', True) else 0,
                prod.get('tipo'),
                prod.get('created_at'), prod.get('updated_at'),
                prod.get('almacen_predeterminado', 'principal')
            ))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_productos(categoria_id: int = None) -> List[Dict]:
        """Obtiene productos de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        if categoria_id:
            cursor.execute(
                "SELECT * FROM productos WHERE activo = 1 AND categoria_id = ? ORDER BY nombre",
                (categoria_id,)
            )
        else:
            cursor.execute("SELECT * FROM productos WHERE activo = 1 ORDER BY nombre")
        
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    @staticmethod
    def get_producto_by_id(producto_id: int) -> Optional[Dict]:
        """Obtiene un producto por ID."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM productos WHERE id = ?", (producto_id,))
        row = cursor.fetchone()
        conn.close()
        
        return dict(row) if row else None
    
    # ==================== EXISTENCIAS ====================
    
    @staticmethod
    def save_existencias(existencias: List[Dict]) -> None:
        """Guarda existencias en la base de datos local."""
        if not existencias:
            return
            
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM existencias")
        
        for ext in existencias:
            almacen = ext.get('almacen')
            if not almacen:
                continue
                
            cursor.execute("""
                INSERT OR REPLACE INTO existencias 
                (id, producto_id, almacen, cantidad, unidad)
                VALUES (?, ?, ?, ?, ?)
            """, (
                ext.get('id'), ext.get('producto_id'), almacen,
                ext.get('cantidad', 0), ext.get('unidad', 'unidad')
            ))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_existencias(producto_id: int = None) -> List[Dict]:
        """Obtiene existencias de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        if producto_id:
            cursor.execute(
                "SELECT * FROM existencias WHERE producto_id = ?",
                (producto_id,)
            )
        else:
            cursor.execute("SELECT * FROM existencias")
        
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    @staticmethod
    def get_existencias_by_producto_almacen(producto_id: int, almacen: str) -> Optional[Dict]:
        """Obtiene existencia por producto y almacén."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute(
            "SELECT * FROM existencias WHERE producto_id = ? AND almacen = ?",
            (producto_id, almacen)
        )
        row = cursor.fetchone()
        conn.close()
        
        return dict(row) if row else None
    
    @staticmethod
    def update_existencia(producto_id: int, almacen: str, cantidad: float, unidad: str = None) -> None:
        """Actualiza la existencia existente o la crea si no existe (sin duplicar)."""
        conn = get_local_conn()
        cursor = conn.cursor()

        almacen = (almacen or "principal").strip()

        if unidad is None:
            cursor.execute("SELECT unidad FROM existencias WHERE producto_id = ? AND almacen = ?",
                         (producto_id, almacen))
            result = cursor.fetchone()
            unidad = result['unidad'] if result and result['unidad'] else 'unidad'

        # Actualizar si ya existe; si no, insertar (evita duplicados por falta de UNIQUE)
        cursor.execute(
            "UPDATE existencias SET cantidad = ?, unidad = ? WHERE producto_id = ? AND almacen = ?",
            (cantidad, unidad, producto_id, almacen)
        )
        if cursor.rowcount == 0:
            cursor.execute(
                "INSERT INTO existencias (producto_id, almacen, cantidad, unidad) VALUES (?, ?, ?, ?)",
                (producto_id, almacen, cantidad, unidad)
            )

        # Limpiar cualquier fila duplicada del mismo (producto_id, almacen)
        cursor.execute(
            "DELETE FROM existencias WHERE id NOT IN ("
            "SELECT MIN(id) FROM existencias WHERE producto_id = ? AND almacen = ?)"
            " AND producto_id = ? AND almacen = ?",
            (producto_id, almacen, producto_id, almacen)
        )

        conn.commit()
        conn.close()

    @staticmethod
    def dedupe_existencias_producto(producto_id: int) -> None:
        """Elimina filas duplicadas de existencias para un producto, conservando la más reciente."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("SELECT DISTINCT almacen FROM existencias WHERE producto_id = ?", (producto_id,))
        almacenes = [r['almacen'] for r in cursor.fetchall()]
        for alm in almacenes:
            cursor.execute(
                "DELETE FROM existencias WHERE id NOT IN ("
                "SELECT MAX(id) FROM existencias WHERE producto_id = ? AND almacen = ?)"
                " AND producto_id = ? AND almacen = ?",
                (producto_id, alm, producto_id, alm)
            )
        conn.commit()
        conn.close()
    
    # ==================== MOVIMIENTOS ====================
    
    @staticmethod
    def save_movimiento(movimiento: Dict, skip_sync: bool = False) -> int:
        """Guarda un movimiento en la BD local."""
        from .sync_queue import get_sync_queue
        from .sync import get_sync_manager
        from config.config import get_settings
        
        conn = get_local_conn()
        cursor = conn.cursor()
        
        # Verificar duplicado antes de guardar
        producto_id = movimiento.get('producto_id')
        tipo = movimiento.get('tipo')
        cantidad = movimiento.get('cantidad')
        fecha = movimiento.get('fecha_movimiento')
        
        cursor.execute("""
            SELECT id FROM movimientos 
            WHERE producto_id = ? AND tipo = ? AND cantidad = ? 
            AND fecha_movimiento >= datetime(?) - 5
        """, (producto_id, tipo, cantidad, fecha))
        
        existing = cursor.fetchone()
        if existing:
            conn.close()
            print(f"[SYNC] Movimiento duplicado ignorado: {existing[0]}")
            return existing[0]
        
        settings = get_settings()
        device_id = settings.DEVICE_IDENTIFIER
        
        cursor.execute("""
            INSERT INTO movimientos 
            (producto_id, factura_id, tipo, cantidad, cantidad_anterior, cantidad_nueva,
             peso_total, peso_registrado, foto_peso_url, registrado_por, observaciones,
             almacen, fecha_movimiento, created_at, device_id, sincronizado)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            movimiento.get('producto_id'), movimiento.get('factura_id'),
            movimiento.get('tipo'), movimiento.get('cantidad'),
            movimiento.get('cantidad_anterior', 0), movimiento.get('cantidad_nueva', 0),
            movimiento.get('peso_total', 0), movimiento.get('peso_registrado'),
            movimiento.get('foto_peso_url'), movimiento.get('registrado_por'),
            movimiento.get('observaciones'), movimiento.get('almacen'),
            movimiento.get('fecha_movimiento'), datetime.now().isoformat(),
            device_id, 0
        ))
        
        last_id = cursor.lastrowid
        conn.commit()
        conn.close()
        
        movimiento['id'] = last_id
        
        if skip_sync:
            return last_id
        
        sync_mgr = get_sync_manager()
        if sync_mgr and sync_mgr.check_connection():
            try:
                from sqlalchemy import text
                from sqlalchemy import create_engine
                
                remote_engine = create_engine(settings.DATABASE_URL)
                
                mov_clean = {k: v for k, v in movimiento.items() 
                           if k not in ('sincronizado', 'created_at', 'id')}
                
                with remote_engine.connect() as conn:
                    cols = ", ".join(mov_clean.keys())
                    vals = ", ".join([f":{k}" for k in mov_clean.keys()])
                    sql = text(f"INSERT INTO movimientos ({cols}) VALUES ({vals})")
                    conn.execute(sql, mov_clean)
                    conn.commit()
                    print(f"[SYNC] Movimiento {last_id} subido inmediatamente")
                
                remote_engine.dispose()
                
                conn = get_local_conn()
                cursor = conn.cursor()
                cursor.execute("UPDATE movimientos SET sincronizado = 1 WHERE id = ?", (last_id,))
                conn.commit()
                conn.close()
                
                return last_id
            except Exception as e:
                print(f"[SYNC] Error sync inmediato: {e}")
                print("[SYNC] Movimiento queda en cola local con sincronizado=0 para reintento automático")
        
        return last_id
    
    @staticmethod
    def get_movimientos(producto_id: int = None, limit: int = 100) -> List[Dict]:
        """Obtiene movimientos de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        if producto_id:
            cursor.execute(
                "SELECT * FROM movimientos WHERE producto_id = ? ORDER BY fecha_movimiento DESC LIMIT ?",
                (producto_id, limit)
            )
        else:
            cursor.execute(
                "SELECT * FROM movimientos ORDER BY fecha_movimiento DESC LIMIT ?",
                (limit,)
            )
        
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    @staticmethod
    def get_movimientos_pendientes() -> List[Dict]:
        """Obtiene movimientos que no han sido sincronizados."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute(
            "SELECT * FROM movimientos WHERE sincronizado = 0 ORDER BY created_at"
        )
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    @staticmethod
    def mark_movimiento_sincronizado(movimiento_id: int) -> None:
        """Marca un movimiento como sincronizado."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute(
            "UPDATE movimientos SET sincronizado = 1 WHERE id = ?",
            (movimiento_id,)
        )
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def clear_movimientos() -> None:
        """Limpia todos los movimientos."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM movimientos")
        conn.commit()
        conn.close()
    
    @staticmethod
    def save_movimientos(movimientos: List[Dict]) -> None:
        """Guarda múltiples movimientos (para sync desde servidor) con deduplicación."""
        if not movimientos:
            return
            
        conn = get_local_conn()
        cursor = conn.cursor()
        
        valid_keys = ['id', 'producto_id', 'factura_id', 'tipo', 'cantidad', 
                      'cantidad_anterior', 'cantidad_nueva', 'peso_total', 
                      'peso_registrado', 'foto_peso_url', 'registrado_por', 
                      'observaciones', 'almacen', 'fecha_movimiento', 
                      'created_at', 'device_id']
        
        inserted_count = 0
        updated_count = 0
        
        for movimientos_chunk in [movimientos[i:i+100] for i in range(0, len(movimientos), 100)]:
            for mov in movimientos_chunk:
                mov_id = mov.get('id')
                producto_id = mov.get('producto_id')
                tipo = mov.get('tipo')
                cantidad = mov.get('cantidad')
                
                if producto_id is None or tipo is None:
                    continue
                if cantidad is None:
                    continue
                
                # Normalizar fecha para comparación (quitar timezone)
                fecha_raw = mov.get('fecha_movimiento')
                fecha_norm = None
                if fecha_raw and isinstance(fecha_raw, str):
                    fecha_norm = fecha_raw.replace('+00:00', '+00').replace('+00', '').replace('T', ' ')
                
                # Deduplicar por ID o por campos lógicos (sin fecha exacta)
                cursor.execute("""
                    SELECT id FROM movimientos 
                    WHERE id = ?
                """, (mov_id,))
                
                if cursor.fetchone():
                    updated_count += 1
                    continue
                
                values = [mov.get(k) for k in valid_keys]
                values.append(1)
                
                placeholders = ','.join(['?' for _ in valid_keys])
                placeholders += ',?'
                
                columns = ','.join(valid_keys) + ',sincronizado'
                
                cursor.execute(f"""
                    INSERT INTO movimientos ({columns})
                    VALUES ({placeholders})
                """, values)
                inserted_count += 1
        
        conn.commit()
        conn.close()
        
        print(f"[SYNC] Movimientos guardados: {inserted_count} nuevos, {updated_count} saltados")
    
    # ==================== FACTURAS ====================
    
    @staticmethod
    def save_facturas(facturas: List[Dict]) -> None:
        """Guarda facturas en la base de datos local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        for fac in facturas:
            cursor.execute("""
                INSERT OR REPLACE INTO facturas 
                (id, numero_factura, proveedor, fecha_factura, fecha_recepcion,
                 total_bruto, total_impuestos, total_neto, estado, observaciones,
                 validada_por, fecha_validacion, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                fac.get('id'), fac.get('numero_factura'), fac.get('proveedor'),
                fac.get('fecha_factura'), fac.get('fecha_recepcion'),
                fac.get('total_bruto', 0), fac.get('total_impuestos', 0),
                fac.get('total_neto', 0), fac.get('estado', 'Pendiente'),
                fac.get('observaciones'), fac.get('validada_por'),
                fac.get('fecha_validacion'), fac.get('created_at'),
                fac.get('updated_at')
            ))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def save_factura_pagos(pagos: List[Dict]) -> None:
        """Guarda pagos de facturas en la base de datos local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        for pago in pagos:
            cursor.execute("""
                INSERT OR REPLACE INTO factura_pagos 
                (id, factura_id, tipo_pago, monto, referencia, tasa_cambio, fecha_pago)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                pago.get('id'), pago.get('factura_id'), pago.get('tipo_pago'),
                pago.get('monto', 0), pago.get('referencia'), pago.get('tasa_cambio'),
                pago.get('fecha_pago')
            ))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_facturas(estado: str = None) -> List[Dict]:
        """Obtiene facturas de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        if estado:
            cursor.execute(
                "SELECT * FROM facturas WHERE estado = ? ORDER BY fecha_factura DESC",
                (estado,)
            )
        else:
            cursor.execute("SELECT * FROM facturas ORDER BY fecha_factura DESC")
        
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    # ==================== REQUISICIONES ====================
    
    @staticmethod
    def save_requisiciones(requisiciones: List[Dict]) -> None:
        if not requisiciones:
            print("[SYNC-DEBUG] save_requisiciones: lista vacía, NO se tocó la tabla")
            return
            
        conn = get_local_conn()
        cursor = conn.cursor()
        
        for req in requisiciones:
            numero_sec = req.get('numero_secuencial')
            if numero_sec is None:
                numero_sec = 0
            
            cursor.execute("""
                INSERT OR REPLACE INTO requisiciones 
                (id, numero, numero_secuencial, origen, destino, estado,
                 observaciones, creada_por, procesada_por, fecha_procesamiento,
                 fecha_creacion, actualizada)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                req.get('id'), req.get('numero'), numero_sec,
                req.get('origen'), req.get('destino'), req.get('estado', 'pendiente'),
                req.get('observaciones'), req.get('creada_por'), req.get('procesada_por'),
                req.get('fecha_procesamiento'), req.get('fecha_creacion'),
                req.get('actualizada')
            ))
            
            # Reemplazar detalles de forma limpia (evita duplicados en descargas)
            cursor.execute(
                "DELETE FROM requisicion_detalles WHERE requisicion_id = ?",
                (req.get('id'),)
            )
            if 'detalles' in req:
                for det in req.get('detalles', []):
                    cursor.execute("""
                        INSERT INTO requisicion_detalles 
                        (requisicion_id, producto_id, ingrediente, cantidad, unidad, cantidad_surtida)
                        VALUES (?, ?, ?, ?, ?, ?)
                    """, (
                        req.get('id'), det.get('producto_id'),
                        det.get('ingrediente'), det.get('cantidad'),
                        det.get('unidad', 'unidad'), det.get('cantidad_surtida', 0)
                    ))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def remap_requisicion_id(local_id: int, remote_id: int) -> None:
        """Tras subir una requisición local, actualiza su id local al id remoto
        para que la descarga y la poda no la dupliquen ni la borren.
        Es seguro si se llama con un id local ya obsoleto (producto de una
        re-edición): en ese caso no hace nada."""
        if local_id == remote_id:
            return
        conn = get_local_conn()
        cursor = conn.cursor()
        # ¿Existe aún el registro local con el id local? (puede ya tener el remoto)
        existe = cursor.execute(
            "SELECT 1 FROM requisiciones WHERE id = ?", (local_id,)
        ).fetchone()
        if not existe:
            conn.close()
            return
        # Eliminar posible registro local obsoleto con el id remoto
        cursor.execute("DELETE FROM requisiciones WHERE id = ?", (remote_id,))
        cursor.execute(
            "UPDATE requisicion_detalles SET requisicion_id = ? WHERE requisicion_id = ?",
            (remote_id, local_id)
        )
        cursor.execute(
            "UPDATE requisiciones SET id = ? WHERE id = ?",
            (remote_id, local_id)
        )
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_requisiciones() -> List[Dict]:
        """Obtiene requisiciones de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM requisiciones ORDER BY fecha_creacion DESC")
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    # ==================== MÉTODOS DE CÁLCULO ====================
    
    @staticmethod
    def recalculate_existencias() -> None:
        """Recalcula las existencias basándose en todos los movimientos."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT producto_id, almacen, tipo, SUM(cantidad) as total_cantidad, SUM(peso_total) as total_peso
            FROM movimientos
            GROUP BY producto_id, almacen, tipo
        """)
        
        movimientos_agrupados = cursor.fetchall()
        
        cursor.execute("DELETE FROM existencias")
        
        stock_por_producto_almacen = {}
        
        for mov in movimientos_agrupados:
            producto_id = mov['producto_id']
            almacen = mov['almacen']
            tipo = mov['tipo']
            total_cantidad = mov['total_cantidad'] or 0
            total_peso = mov['total_peso'] or 0
            
            if not producto_id:
                continue
            if not almacen:
                almacen = 'principal'
            
            cursor.execute("SELECT es_pesable, unidad_medida FROM productos WHERE id = ?", (producto_id,))
            prod_row = cursor.fetchone()
            es_pesable = prod_row['es_pesable'] if prod_row else 0
            unidad = prod_row['unidad_medida'] if prod_row else 'unidad'
            
            if es_pesable:
                cantidad = total_peso
            else:
                cantidad = total_cantidad
            
            key = (producto_id, almacen)
            if key not in stock_por_producto_almacen:
                stock_por_producto_almacen[key] = {'cantidad': 0, 'unidad': unidad}
            
            if tipo == 'entrada':
                stock_por_producto_almacen[key]['cantidad'] += cantidad
            elif tipo == 'salida':
                stock_por_producto_almacen[key]['cantidad'] -= cantidad
        
        for (producto_id, almacen), data in stock_por_producto_almacen.items():
            if producto_id and almacen and data['cantidad'] is not None:
                final_stock = data['cantidad']
                
                if final_stock < 0:
                    print(f"[WARN] Stock negativo detectado: producto={producto_id}, almacen={almacen}, stock={final_stock}")
                
                cursor.execute("""
                    INSERT OR REPLACE INTO existencias (producto_id, almacen, cantidad, unidad)
                    VALUES (?, ?, ?, ?)
                """, (producto_id, almacen, final_stock, data['unidad']))
        
        conn.commit()
        conn.close()
    
# ==================== METADATOS DE SYNC ====================
    # Delegamos en sync_queue.py para mantener un solo source of truth
    
    def set_last_sync(key: str, timestamp: str = None) -> None:
        SyncQueue.set_last_sync(timestamp or datetime.now().isoformat())

    def get_last_sync(key: str) -> Optional[str]:
        return SyncQueue.get_last_sync()
    
    # ==================== OPERACIONES PENDIENTES ====================
    
    @staticmethod
    def add_pending_operation(table_name: str, operation: str, record_id: int, data: Dict) -> None:
        """Agrega una operación pendiente de sincronización."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT INTO pending_operations (table_name, operation, record_id, data, created_at)
            VALUES (?, ?, ?, ?, ?)
        """, (
            table_name, operation, record_id, json.dumps(data, default=str),
            datetime.now().isoformat()
        ))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_pending_operations() -> List[Dict]:
        """Obtiene todas las operaciones pendientes."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM pending_operations ORDER BY created_at")
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    @staticmethod
    def clear_pending_operation(operation_id: int) -> None:
        """Elimina una operación pendiente."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM pending_operations WHERE id = ?", (operation_id,))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_pending_count() -> int:
        """Retorna el número de operaciones pendientes."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("SELECT COUNT(*) as count FROM pending_operations")
        row = cursor.fetchone()
        conn.close()
        
        return row['count'] if row else 0

    @staticmethod
    def get_usuario_dispositivo() -> dict | None:
        """Devuelve el usuario registrado en este dispositivo, o None."""
        import hashlib
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM dispositivo_usuario LIMIT 1")
        row = cursor.fetchone()
        conn.close()
        return dict(row) if row else None
    
    @staticmethod
    def registrar_usuario_dispositivo(nombre: str, pin: str | None = None) -> None:
        """Registra el usuario de este dispositivo (solo una vez)."""
        import hashlib
        pin_hash = None
        if pin and pin.strip():
            pin_hash = hashlib.sha256(pin.strip().encode()).hexdigest()
        
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM dispositivo_usuario")
        cursor.execute(
            "INSERT INTO dispositivo_usuario (nombre, pin_hash, configurado_en) VALUES (?, ?, ?)",
            (nombre.strip(), pin_hash, datetime.now().isoformat())
        )
        conn.commit()
        conn.close()
    
    @staticmethod
    def verificar_pin(pin: str) -> bool:
        """Verifica el PIN del usuario."""
        import hashlib
        if not pin:
            return False
        
        pin_hash = hashlib.sha256(pin.encode()).hexdigest()
        
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("SELECT pin_hash FROM dispositivo_usuario LIMIT 1")
        row = cursor.fetchone()
        conn.close()
        
        return row and row['pin_hash'] == pin_hash
    
    @staticmethod
    def delete_orphaned_records(table_name: str, remote_ids: List[int], key_column: str = None) -> int:
        """
        Elimina registros locales que no están en la lista de IDs remotos
        y no están pendientes de sincronización en la cola.
        """
        import json

        conn = get_local_conn()
        cursor = conn.cursor()

        # DEBUG: verificar cuántos registros hay antes de podar
        if table_name == 'requisiciones':
            cursor.execute(f"SELECT COUNT(*) as cnt FROM {table_name}")
            debug_cnt = cursor.fetchone()['cnt']
            print(f"[SYNC-DEBUG] requisiciones antes de podar: {debug_cnt} registros, remote_ids={remote_ids}")

        # 1. Obtener valores clave de la cola de sync pendientes para esta tabla
        cursor.execute("SELECT data FROM sync_queue WHERE table_name = ? AND status = 'pending'", (table_name,))
        pending_rows = cursor.fetchall()

        pending_keys = []
        if key_column:
            for row in pending_rows:
                try:
                    p_data = json.loads(row[0])
                    if key_column in p_data:
                        pending_keys.append(p_data[key_column])
                except:
                    pass

        # Si el servidor devolvió 0 filas:
        #  - Tablas con creación local (productos, categorías, facturas, etc.):
        #    NO podamos, para no borrar datos locales no sincronados por un fallo
        #    transitorio de lectura.
        #  - 'requisiciones' es una tabla de SOLO DESCARGA: si ya no existen en el
        #    servidor, deben desaparecer también en local.
        if not remote_ids:
            if table_name != 'requisiciones':
                conn.close()
                return 0
            query = f"DELETE FROM {table_name} WHERE 1=1"
            params = []
        else:
            placeholders = ','.join(['?' for _ in remote_ids])
            query = f"DELETE FROM {table_name} WHERE id NOT IN ({placeholders})"
            params = list(remote_ids)

        if key_column and pending_keys:
            key_placeholders = ','.join(['?' for _ in pending_keys])
            query += f" AND {key_column} NOT IN ({key_placeholders})"
            params.extend(pending_keys)

        cursor.execute(query, params)
        deleted = cursor.rowcount

        # Caso especial para requisiciones: también eliminar detalles huérfanos
        if table_name == 'requisiciones':
            if remote_ids:
                dph = ','.join(['?' for _ in remote_ids])
                cursor.execute(f"DELETE FROM requisicion_detalles WHERE requisicion_id NOT IN ({dph})", list(remote_ids))
            else:
                cursor.execute("DELETE FROM requisicion_detalles WHERE requisicion_id NOT IN (SELECT id FROM requisiciones)")

        conn.commit()
        conn.close()

        if deleted > 0 or table_name == 'requisiciones':
            print(f"[SYNC] {deleted} registros huérfanos eliminados de la tabla local '{table_name}'")
        return deleted

    @staticmethod
    def eliminar_usuario_dispositivo() -> None:
        """Resetea el usuario (para cambio de operador)."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM dispositivo_usuario")
        conn.commit()
        conn.close()

    # ==================== RECETAS ====================

    @staticmethod
    def get_recetas(activo: bool = True) -> List[Dict]:
        """Obtiene todas las recetas."""
        conn = get_local_conn()
        cursor = conn.cursor()
        if activo:
            cursor.execute("SELECT * FROM recetas WHERE activo = 1 ORDER BY nombre")
        else:
            cursor.execute("SELECT * FROM recetas ORDER BY nombre")
        rows = cursor.fetchall()
        conn.close()
        return [dict(row) for row in rows]

    @staticmethod
    def get_receta_by_id(receta_id: int) -> Optional[Dict]:
        """Obtiene una receta por ID."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM recetas WHERE id = ?", (receta_id,))
        row = cursor.fetchone()
        conn.close()
        return dict(row) if row else None

    @staticmethod
    def save_receta(receta: Dict) -> int:
        """Guarda una receta y retorna su ID."""
        conn = get_local_conn()
        cursor = conn.cursor()
        now = datetime.now().isoformat()
        receta_id = receta.get('id')
        if receta_id:
            cursor.execute("""
                UPDATE recetas SET nombre=?, tipo=?, producto_base_id=?, producto_final_id=?,
                cantidad_producida=?, activo=?, updated_at=?
                WHERE id=?
            """, (
                receta.get('nombre'), receta.get('tipo'),
                receta.get('producto_base_id'), receta.get('producto_final_id'),
                receta.get('cantidad_producida', 1),
                1 if receta.get('activo', True) else 0,
                now, receta_id
            ))
        else:
            cursor.execute("""
                INSERT INTO recetas (nombre, tipo, producto_base_id, producto_final_id,
                cantidad_producida, activo, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                receta.get('nombre'), receta.get('tipo'),
                receta.get('producto_base_id'), receta.get('producto_final_id'),
                receta.get('cantidad_producida', 1),
                1 if receta.get('activo', True) else 0,
                now, now
            ))
            receta_id = cursor.lastrowid
        conn.commit()
        conn.close()
        return receta_id

    @staticmethod
    def delete_receta(receta_id: int) -> None:
        """Elimina una receta y sus componentes."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM receta_componentes WHERE receta_id = ?", (receta_id,))
        cursor.execute("DELETE FROM recetas WHERE id = ?", (receta_id,))
        conn.commit()
        conn.close()

    # ==================== RECETA COMPONENTES ====================

    @staticmethod
    def get_componentes_by_receta(receta_id: int) -> List[Dict]:
        """Obtiene los componentes de una receta."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT rc.*, p.nombre as producto_nombre, p.tipo as producto_tipo
            FROM receta_componentes rc
            LEFT JOIN productos p ON rc.producto_id = p.id
            WHERE rc.receta_id = ?
            ORDER BY rc.tipo_componente, p.nombre
        """, (receta_id,))
        rows = cursor.fetchall()
        conn.close()
        return [dict(row) for row in rows]

    @staticmethod
    def save_componentes(receta_id: int, componentes: List[Dict]) -> None:
        """Reemplaza todos los componentes de una receta."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM receta_componentes WHERE receta_id = ?", (receta_id,))
        for comp in componentes:
            cursor.execute("""
                INSERT INTO receta_componentes (receta_id, producto_id, cantidad, unidad, tipo_componente)
                VALUES (?, ?, ?, ?, ?)
            """, (
                receta_id, comp.get('producto_id'), comp.get('cantidad'),
                comp.get('unidad', 'unidad'), comp.get('tipo_componente')
            ))
        conn.commit()
        conn.close()

    # ==================== PRODUCCIONES ====================

    @staticmethod
    def get_producciones(limit: int = 50) -> List[Dict]:
        """Obtiene el historial de producciones."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT p.*, r.nombre as receta_nombre, r.tipo as receta_tipo
            FROM producciones p
            LEFT JOIN recetas r ON p.receta_id = r.id
            ORDER BY p.fecha_produccion DESC
            LIMIT ?
        """, (limit,))
        rows = cursor.fetchall()
        conn.close()
        return [dict(row) for row in rows]

    @staticmethod
    def save_produccion(produccion: Dict) -> int:
        """Guarda una producción y retorna su ID."""
        conn = get_local_conn()
        cursor = conn.cursor()
        now = datetime.now().isoformat()
        cursor.execute("""
            INSERT INTO producciones (receta_id, cantidad, estado, usuario, observaciones, fecha_produccion, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (
            produccion.get('receta_id'), produccion.get('cantidad'),
            produccion.get('estado', 'completado'), produccion.get('usuario'),
            produccion.get('observaciones'), produccion.get('fecha_produccion', now), now
        ))
        prod_id = cursor.lastrowid
        conn.commit()
        conn.close()
        return prod_id

    @staticmethod
    def save_produccion_detalle(detalle: Dict) -> int:
        """Guarda un detalle de producción."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO produccion_detalles (produccion_id, producto_id, tipo, cantidad, unidad, movimiento_id)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (
            detalle.get('produccion_id'), detalle.get('producto_id'),
            detalle.get('tipo'), detalle.get('cantidad'),
            detalle.get('unidad', 'unidad'), detalle.get('movimiento_id')
        ))
        det_id = cursor.lastrowid
        conn.commit()
        conn.close()
        return det_id

    @staticmethod
    def get_detalles_by_produccion(produccion_id: int) -> List[Dict]:
        """Obtiene los detalles de una producción."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT pd.*, p.nombre as producto_nombre
            FROM produccion_detalles pd
            LEFT JOIN productos p ON pd.producto_id = p.id
            WHERE pd.produccion_id = ?
            ORDER BY pd.tipo, p.nombre
        """, (produccion_id,))
        rows = cursor.fetchall()
        conn.close()
        return [dict(row) for row in rows]


def ensure_local_db():
    """Asegura que la BD local existe. Llamar después de set_db_path()."""
    from usr.logger import get_logger
    logger = get_logger("local_replica")
    try:
        logger.info("Inicializando base de datos local...")
        init_local_db()
        logger.info("Base de datos local inicializada")
    except Exception as e:
        logger.error(f"Error al inicializar BD: {e}")
        raise
