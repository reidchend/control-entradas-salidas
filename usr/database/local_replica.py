"""
Réplica local SQLite para trabajo offline.
Almacena una copia de los datos de Supabase para acceso offline.
"""
import sqlite3
import json
import uuid
from datetime import datetime
from typing import Optional, List, Dict, Any
from config.config import get_settings

LOCAL_DB_PATH = get_settings().LOCAL_DB_PATH

def get_local_conn():
    """Obtiene conexión a la base de datos local."""
    conn = sqlite3.connect(LOCAL_DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_local_db():
    """Inicializa la base de datos local con todas las tablas."""
    conn = get_local_conn()
    cursor = conn.cursor()
    
    # Tabla de categorías
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS local_categorias (
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
    
    # Tabla de productos
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS local_productos (
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
            created_at TEXT,
            updated_at TEXT,
            almacen_predeterminado TEXT DEFAULT 'principal',
            FOREIGN KEY (categoria_id) REFERENCES local_categorias(id)
        )
    """)
    
    # Tabla de existencias (stock por producto/almacén)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS local_existencias (
            id INTEGER PRIMARY KEY,
            producto_id INTEGER NOT NULL,
            almacen TEXT NOT NULL,
            cantidad REAL DEFAULT 0,
            unidad TEXT DEFAULT 'unidad',
            FOREIGN KEY (producto_id) REFERENCES local_productos(id)
        )
    """)
    
    # Tabla de movimientos con device_id para tracking
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS local_movimientos (
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
            sincronizado INTEGER DEFAULT 0,
            FOREIGN KEY (producto_id) REFERENCES local_productos(id),
            FOREIGN KEY (factura_id) REFERENCES local_facturas(id)
        )
    """)
    
    # Tabla de facturas
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS local_facturas (
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
    
    # Tabla de requisiciones
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS local_requisiciones (
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
    
    # Tabla de detalles de requisición
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS local_requisicion_detalles (
            id INTEGER PRIMARY KEY,
            requisicion_id INTEGER NOT NULL,
            producto_id INTEGER,
            ingrediente TEXT NOT NULL,
            cantidad REAL NOT NULL,
            unidad TEXT DEFAULT 'unidad',
            cantidad_surtida REAL DEFAULT 0,
            FOREIGN KEY (requisicion_id) REFERENCES local_requisiciones(id),
            FOREIGN KEY (producto_id) REFERENCES local_productos(id)
        )
    """)
    
    # Tabla de metadatos de sincronización
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS sync_metadata (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TEXT
        )
    """)
    
    # Tabla de cola de operaciones pendientes
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
    
    conn.commit()
    conn.close()

class LocalReplica:
    """Clase para manejar la réplica local de datos."""
    
    @staticmethod
    def create_tables():
        """Crea todas las tablas locales."""
        init_local_db()
    
    # ==================== CATEGORÍAS ====================
    
    @staticmethod
    def save_categorias(categorias: List[Dict]) -> None:
        """Guarda categorías en la base de datos local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM local_categorias")
        
        for cat in categorias:
            cursor.execute("""
                INSERT OR REPLACE INTO local_categorias 
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
        
        cursor.execute("SELECT * FROM local_categorias WHERE activo = 1 ORDER BY nombre")
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    # ==================== PRODUCTOS ====================
    
    @staticmethod
    def save_productos(productos: List[Dict]) -> None:
        """Guarda productos en la base de datos local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM local_productos")
        
        for prod in productos:
            cursor.execute("""
                INSERT OR REPLACE INTO local_productos 
                (id, nombre, codigo, descripcion, categoria_id, es_pesable, 
                 requiere_foto_peso, peso_unitario, unidad_medida, stock_actual, 
                 stock_minimo, activo, created_at, updated_at, almacen_predeterminado)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                prod.get('id'), prod.get('nombre'), prod.get('codigo'),
                prod.get('descripcion'), prod.get('categoria_id'),
                1 if prod.get('es_pesable') else 0,
                1 if prod.get('requiere_foto_peso') else 0,
                prod.get('peso_unitario'), prod.get('unidad_medida', 'unidad'),
                prod.get('stock_actual', 0), prod.get('stock_minimo', 0),
                1 if prod.get('activo', True) else 0,
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
                "SELECT * FROM local_productos WHERE activo = 1 AND categoria_id = ? ORDER BY nombre",
                (categoria_id,)
            )
        else:
            cursor.execute("SELECT * FROM local_productos WHERE activo = 1 ORDER BY nombre")
        
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    @staticmethod
    def get_producto_by_id(producto_id: int) -> Optional[Dict]:
        """Obtiene un producto por ID."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM local_productos WHERE id = ?", (producto_id,))
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
        
        cursor.execute("DELETE FROM local_existencias")
        
        for ext in existencias:
            almacen = ext.get('almacen')
            if not almacen:
                continue
                
            cursor.execute("""
                INSERT OR REPLACE INTO local_existencias 
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
                "SELECT * FROM local_existencias WHERE producto_id = ?",
                (producto_id,)
            )
        else:
            cursor.execute("SELECT * FROM local_existencias")
        
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    @staticmethod
    def get_existencias_by_producto_almacen(producto_id: int, almacen: str) -> Optional[Dict]:
        """Obtiene existencia por producto y almacén."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute(
            "SELECT * FROM local_existencias WHERE producto_id = ? AND almacen = ?",
            (producto_id, almacen)
        )
        row = cursor.fetchone()
        conn.close()
        
        return dict(row) if row else None
    
    @staticmethod
    def update_existencia(producto_id: int, almacen: str, cantidad: float) -> None:
        """Actualiza o crea existencia."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT OR REPLACE INTO local_existencias (producto_id, almacen, cantidad, unidad)
            VALUES (?, ?, ?, 
                (SELECT unidad FROM local_existencias WHERE producto_id = ? AND almacen = ? LIMIT 1)
            )
        """, (producto_id, almacen, cantidad, producto_id, almacen))
        
        conn.commit()
        conn.close()
    
    # ==================== MOVIMIENTOS ====================
    
    @staticmethod
    def save_movimiento(movimiento: Dict) -> int:
        """Guarda un movimiento en la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        settings = get_settings()
        device_id = settings.DEVICE_IDENTIFIER
        
        cursor.execute("""
            INSERT INTO local_movimientos 
            (producto_id, factura_id, tipo, cantidad, cantidad_anterior, cantidad_nueva,
             peso_total, peso_registrado, foto_peso_url, registrado_por, observaciones,
             almacen, fecha_movimiento, created_at, device_id, sincronizado)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
        """, (
            movimiento.get('producto_id'), movimiento.get('factura_id'),
            movimiento.get('tipo'), movimiento.get('cantidad'),
            movimiento.get('cantidad_anterior', 0), movimiento.get('cantidad_nueva', 0),
            movimiento.get('peso_total', 0), movimiento.get('peso_registrado'),
            movimiento.get('foto_peso_url'), movimiento.get('registrado_por'),
            movimiento.get('observaciones'), movimiento.get('almacen'),
            movimiento.get('fecha_movimiento'), datetime.now().isoformat(),
            device_id
        ))
        
        last_id = cursor.lastrowid
        conn.commit()
        conn.close()
        
        return last_id
    
    @staticmethod
    def get_movimientos(producto_id: int = None, limit: int = 100) -> List[Dict]:
        """Obtiene movimientos de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        if producto_id:
            cursor.execute(
                "SELECT * FROM local_movimientos WHERE producto_id = ? ORDER BY fecha_movimiento DESC LIMIT ?",
                (producto_id, limit)
            )
        else:
            cursor.execute(
                "SELECT * FROM local_movimientos ORDER BY fecha_movimiento DESC LIMIT ?",
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
            "SELECT * FROM local_movimientos WHERE sincronizado = 0 ORDER BY created_at"
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
            "UPDATE local_movimientos SET sincronizado = 1 WHERE id = ?",
            (movimiento_id,)
        )
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def save_movimientos(movimientos: List[Dict]) -> None:
        """Guarda múltiples movimientos (para sync desde servidor)."""
        if not movimientos:
            return
            
        conn = get_local_conn()
        cursor = conn.cursor()
        
        valid_keys = ['id', 'producto_id', 'factura_id', 'tipo', 'cantidad', 
                      'cantidad_anterior', 'cantidad_nueva', 'peso_total', 
                      'peso_registrado', 'foto_peso_url', 'registrado_por', 
                      'observaciones', 'almacen', 'fecha_movimiento', 
                      'created_at', 'device_id']
        
        for mov in movimientos:
            values = [mov.get(k) for k in valid_keys]
            values.append(1)  # sincronizado = 1
            
            placeholders = ','.join(['?' for _ in valid_keys])
            placeholders += ',?'
            
            columns = ','.join(valid_keys) + ',sincronizado'
            
            cursor.execute(f"""
                INSERT OR REPLACE INTO local_movimientos ({columns})
                VALUES ({placeholders})
            """, values)
        
        conn.commit()
        conn.close()
    
    # ==================== FACTURAS ====================
    
    @staticmethod
    def save_facturas(facturas: List[Dict]) -> None:
        """Guarda facturas en la base de datos local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM local_facturas")
        
        for fac in facturas:
            cursor.execute("""
                INSERT OR REPLACE INTO local_facturas 
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
    def get_facturas(estado: str = None) -> List[Dict]:
        """Obtiene facturas de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        if estado:
            cursor.execute(
                "SELECT * FROM local_facturas WHERE estado = ? ORDER BY fecha_factura DESC",
                (estado,)
            )
        else:
            cursor.execute("SELECT * FROM local_facturas ORDER BY fecha_factura DESC")
        
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    # ==================== REQUISICIONES ====================
    
    @staticmethod
    def save_requisiciones(requisiciones: List[Dict]) -> None:
        if not requisiciones:
            return
            
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM local_requisiciones")
        cursor.execute("DELETE FROM local_requisicion_detalles")
        
        for req in requisiciones:
            numero_sec = req.get('numero_secuencial')
            if numero_sec is None:
                numero_sec = 0
            
            cursor.execute("""
                INSERT OR REPLACE INTO local_requisiciones 
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
            
            if 'detalles' in req:
                for det in req.get('detalles', []):
                    cursor.execute("""
                        INSERT OR REPLACE INTO local_requisicion_detalles 
                        (id, requisicion_id, producto_id, ingrediente, cantidad, unidad, cantidad_surtida)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (
                        det.get('id'), req.get('id'), det.get('producto_id'),
                        det.get('ingrediente'), det.get('cantidad'),
                        det.get('unidad', 'unidad'), det.get('cantidad_surtida', 0)
                    ))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_requisiciones() -> List[Dict]:
        """Obtiene requisiciones de la BD local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM local_requisiciones ORDER BY fecha_creacion DESC")
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
            SELECT producto_id, almacen, tipo, SUM(cantidad) as total
            FROM local_movimientos
            GROUP BY producto_id, almacen, tipo
        """)
        
        movimientos_agrupados = cursor.fetchall()
        
        cursor.execute("DELETE FROM local_existencias")
        
        stock_por_producto_almacen = {}
        
        for mov in movimientos_agrupados:
            producto_id = mov['producto_id']
            almacen = mov['almacen']
            tipo = mov['tipo']
            total = mov['total'] or 0
            
            if not producto_id or not almacen:
                continue
            
            key = (producto_id, almacen)
            if key not in stock_por_producto_almacen:
                stock_por_producto_almacen[key] = 0
            
            if tipo == 'entrada':
                stock_por_producto_almacen[key] += total
            elif tipo == 'salida':
                stock_por_producto_almacen[key] -= total
        
        for (producto_id, almacen), cantidad in stock_por_producto_almacen.items():
            if producto_id and almacen and cantidad is not None:
                cursor.execute("""
                    INSERT OR REPLACE INTO local_existencias (producto_id, almacen, cantidad, unidad)
                    VALUES (?, ?, ?, 
                        (SELECT unidad_medida FROM local_productos WHERE id = ? LIMIT 1)
                    )
                """, (producto_id, almacen, cantidad, producto_id))
        
        conn.commit()
        conn.close()
    
    # ==================== METADATOS DE SYNC ====================
    
    @staticmethod
    def set_last_sync(key: str, timestamp: str = None) -> None:
        """Guarda el timestamp del último sync."""
        if timestamp is None:
            timestamp = datetime.now().isoformat()
        
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT OR REPLACE INTO sync_metadata (key, value, updated_at)
            VALUES (?, ?, ?)
        """, (key, timestamp, datetime.now().isoformat()))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_last_sync(key: str) -> Optional[str]:
        """Obtiene el timestamp del último sync."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("SELECT value FROM sync_metadata WHERE key = ?", (key,))
        row = cursor.fetchone()
        conn.close()
        
        return row['value'] if row else None
    
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

init_local_db()
