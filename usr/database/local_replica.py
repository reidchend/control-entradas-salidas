"""
Réplica local SQLite para trabajo offline.
Almacena una copia de los datos de Supabase para acceso offline.
"""
from datetime import datetime
from typing import Optional, List, Dict, Any
from usr.database.conn import get_local_conn
from config.config import get_settings

from usr.database.sync_queue import (
    set_last_sync as _sync_set_last_sync,
    get_last_sync as _sync_get_last_sync,
    add_pending_sync,
    get_pending_sync,
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
            created_at TEXT,
            updated_at TEXT,
            almacen_predeterminado TEXT DEFAULT 'principal'
        )
    """)
    
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
        """Actualiza o crea existencia."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        if unidad is None:
            cursor.execute("SELECT unidad FROM existencias WHERE producto_id = ? AND almacen = ?", 
                         (producto_id, almacen))
            result = cursor.fetchone()
            unidad = result['unidad'] if result and result['unidad'] else 'unidad'
        
        cursor.execute("""
            INSERT OR REPLACE INTO existencias (producto_id, almacen, cantidad, unidad)
            VALUES (?, ?, ?, ?)
        """, (producto_id, almacen, cantidad, unidad))
        
        conn.commit()
        conn.close()
    
    # ==================== MOVIMIENTOS ====================
    
    @staticmethod
    def save_movimiento(movimiento: Dict, skip_sync: bool = False) -> int:
        """Guarda un movimiento en la BD local."""
        from .sync_queue import get_sync_queue
        from .base import check_connection
        
        conn = get_local_conn()
        cursor = conn.cursor()
        
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
        
        if check_connection():
            try:
                from sqlalchemy import text
                from .base import get_session
                
                session_maker = get_session()
                mov_clean = {k: v for k, v in movimiento.items() 
                           if k not in ('sincronizado', 'created_at', 'id')}
                
                with session_maker() as db:
                    cols = ", ".join(mov_clean.keys())
                    vals = ", ".join([f":{k}" for k in mov_clean.keys()])
                    sql = text(f"INSERT INTO movimientos ({cols}) VALUES ({vals})")
                    db.execute(sql, mov_clean)
                    db.commit()
                    print(f"[SYNC] Movimiento {last_id} subido inmediatamente")
                    
                    conn = get_local_conn()
                    cursor = conn.cursor()
                    cursor.execute("UPDATE movimientos SET sincronizado = 1 WHERE id = ?", (last_id,))
                    conn.commit()
                    conn.close()
                    
                    return last_id
            except Exception as e:
                print(f"[SYNC] Error sync inmediato: {e}, guardando en cola")
        
        queue = get_sync_queue()
        queue.add_pending('movimientos', 'insert', movimiento)
        
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
    def save_movimientos(movimientos: List[Dict]) -> None:
        """Guarda múltiples movimientos (para sync desde servidor) con deduplicación."""
        if not movimientos:
            return
            
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM movimientos WHERE sincronizado = 1")
        
        valid_keys = ['id', 'producto_id', 'factura_id', 'tipo', 'cantidad', 
                      'cantidad_anterior', 'cantidad_nueva', 'peso_total', 
                      'peso_registrado', 'foto_peso_url', 'registrado_por', 
                      'observaciones', 'almacen', 'fecha_movimiento', 
                      'created_at', 'device_id']
        
        inserted_ids = set()
        
        for mov in movimientos:
            mov_id = mov.get('id')
            producto_id = mov.get('producto_id')
            tipo = mov.get('tipo')
            cantidad = mov.get('cantidad')
            fecha = mov.get('fecha_movimiento')
            
            if not all([producto_id, tipo]):
                continue
            
            key = (producto_id, tipo, cantidad, fecha)
            if key in inserted_ids:
                continue
            
            cursor.execute("""
                SELECT id FROM movimientos 
                WHERE producto_id = ? AND tipo = ? AND cantidad = ? AND fecha_movimiento = ?
            """, (producto_id, tipo, cantidad, fecha))
            existing = cursor.fetchone()
            
            if existing:
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
            
            inserted_ids.add(key)
        
        conn.commit()
        conn.close()
    
    # ==================== FACTURAS ====================
    
    @staticmethod
    def save_facturas(facturas: List[Dict]) -> None:
        """Guarda facturas en la base de datos local."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM facturas")
        
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
            return
            
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM requisiciones")
        cursor.execute("DELETE FROM requisicion_detalles")
        
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
            
            if 'detalles' in req:
                for det in req.get('detalles', []):
                    cursor.execute("""
                        INSERT OR REPLACE INTO requisicion_detalles 
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
            
            if not producto_id or not almacen:
                continue
            
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
                cursor.execute("""
                    INSERT OR REPLACE INTO existencias (producto_id, almacen, cantidad, unidad)
                    VALUES (?, ?, ?, ?)
                """, (producto_id, almacen, data['cantidad'], data['unidad']))
        
        conn.commit()
        conn.close()
    
# ==================== METADATOS DE SYNC ====================
    # Delegamos en sync_queue.py para mantener un solo source of truth
    
    def set_last_sync(key: str, timestamp: str = None) -> None:
        _sync_set_last_sync(key, timestamp)

    def get_last_sync(key: str) -> Optional[str]:
        return _sync_get_last_sync(key)
    
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
    def eliminar_usuario_dispositivo() -> None:
        """Resetea el usuario (para cambio de operador)."""
        conn = get_local_conn()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM dispositivo_usuario")
        conn.commit()
        conn.close()

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
