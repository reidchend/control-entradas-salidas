"""
Sincronización Bidireccional con SQLAlchemy - maneja conexión y offline para multi-dispositivo
"""
import threading
import socket
from datetime import datetime
from sqlalchemy import text
from .cache import (
    get_cache, set_cache, get_cache_any_age,
    add_pending_sync, get_pending_sync, clear_pending_sync,
    set_last_sync, get_last_sync
)

class SyncManager:
    def __init__(self, engine_getter):
        self._engine_getter = engine_getter
        self._session_local_getter = None
        self.is_online = True
        self._on_connection_change = None
        self._retry_count = {}
        self._max_retries = 3
        self._sync_thread = None
        self._stop_event = threading.Event()
    
    @property
    def engine(self):
        return self._engine_getter()
    
    def set_session_local_getter(self, session_getter):
        """Configura el getter para sessionmaker - evita error de contexto"""
        self._session_local_getter = session_getter
    
    def _get_session_maker(self):
        if self._session_local_getter:
            return self._session_local_getter()
        return None
    
    def check_connection(self) -> bool:
        """Verifica si hay conexión a la base de datos"""
        try:
            with self.engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            was_offline = not self.is_online
            self.is_online = True
            
            if was_offline and self._on_connection_change:
                self._on_connection_change(True)
            return True
        except Exception as e:
            was_online = self.is_online
            self.is_online = False
            
            if was_online and self._on_connection_change:
                self._on_connection_change(False)
            return False
    
    def set_connection_callback(self, callback):
        """Callback para cambios de conexión"""
        self._on_connection_change = callback
    
    def sync_pending_changes(self, session_getter=None) -> bool:
        """Sincroniza cambios pendientes con la BD"""
        if session_getter is None:
            session_getter = self._session_local_getter
        
        if not self.check_connection():
            return False
        
        pending = get_pending_sync()
        if not pending:
            return True
        
        synced_ids = []
        
        for item in pending:
            table = item['table_name']
            record_id = item['record_id']
            action = item['action']
            
            key = f"{table}_{record_id}_{action}"
            retries = self._retry_count.get(key, 0)
            
            if retries >= self._max_retries:
                synced_ids.append(item['id'])
                continue
            
            try:
                session_maker = session_getter()
                with session_maker() as db:
                    if action == 'INSERT':
                        self._sync_insert(db, table, item['data'])
                    elif action == 'UPDATE':
                        self._sync_update(db, table, record_id, item['data'])
                    elif action == 'DELETE':
                        self._sync_delete(db, table, record_id)
                    
                    db.commit()
                synced_ids.append(item['id'])
                if key in self._retry_count:
                    del self._retry_count[key]
            except Exception as e:
                print(f"Error sync {action} {table}: {e}")
                self._retry_count[key] = retries + 1
        
        if synced_ids:
            clear_pending_sync(synced_ids)
        
        return True
    
    def _sync_insert(self, db, table, data):
        import json
        data_dict = json.loads(data) if data else {}
        columns = ", ".join(data_dict.keys())
        placeholders = ", ".join([f":{k}" for k in data_dict.keys()])
        stmt = text(f"INSERT INTO {table} ({columns}) VALUES ({placeholders})")
        db.execute(stmt, data_dict)
    
    def _sync_update(self, db, table, record_id, data):
        import json
        data_dict = json.loads(data) if data else {}
        set_clause = ", ".join([f"{k} = :{k}" for k in data_dict.keys()])
        stmt = text(f"UPDATE {table} SET {set_clause} WHERE id = :id")
        data_dict['id'] = record_id
        db.execute(stmt, data_dict)
    
    def _sync_delete(self, db, table, record_id):
        stmt = text(f"DELETE FROM {table} WHERE id = :id")
        db.execute(stmt, {'id': record_id})
    
    def download_from_server(self, tables: list, session_getter=None) -> dict:
        """Descarga datos del servidor para las tablas especificadas"""
        if session_getter is None:
            session_getter = self._session_local_getter
        
        if not self.check_connection():
            return {}
        
        results = {}
        last_sync = get_last_sync("full_download") or datetime.min
        
        for table in tables:
            try:
                session_maker = session_getter()
                with session_maker() as db:
                    query = text(f"SELECT * FROM {table}")
                    
                    if last_sync != datetime.min:
                        # Solo下载 cambios posteriores al último sync
                        if table in ["movimientos", "facturas"]:
                            col_fecha = "fecha_movimiento" if table == "movimientos" else "fecha_factura"
                            query = text(f"SELECT * FROM {table} WHERE {col_fecha} > :last_sync")
                            result = db.execute(query, {'last_sync': last_sync.isoformat()})
                        else:
                            query = text(f"SELECT * FROM {table}")
                            result = db.execute(query)
                    else:
                        query = text(f"SELECT * FROM {table}")
                        result = db.execute(query)
                    
                    rows = result.fetchall()
                    results[table] = [dict(row._mapping) for row in rows]
                    set_cache(f"server_{table}", results[table], ttl_seconds=3600)
            except Exception as e:
                print(f"Error descargando {table}: {e}")
        
        if results:
            set_last_sync("full_download")
        
        return results
    
    def start_background_sync(self, session_getter, interval_seconds: int = 30):
        """Inicia sincronización en segundo plano"""
        if self._sync_thread and self._sync_thread.is_alive():
            return
        
        self._session_local_getter = session_getter
        self._stop_event.clear()
        self._sync_thread = threading.Thread(
            target=self._background_sync_loop,
            args=(interval_seconds,),
            daemon=True
        )
        self._sync_thread.start()
    
    def stop_background_sync(self):
        """Detiene sincronización"""
        self._stop_event.set()
        if self._sync_thread:
            self._sync_thread.join(timeout=2)
    
    def _background_sync_loop(self, interval):
        while not self._stop_event.is_set():
            self.sync_pending_changes()
            
            if self.is_online:
                self.download_from_server(["movimientos", "facturas", "productos"])
            
            self._stop_event.wait(interval)
    
    def get_connection_status(self) -> dict:
        """Estado de conexión"""
        return {
            "online": self.is_online,
            "pending_count": len(get_pending_sync()),
            "last_sync": get_last_sync("full_download")
        }

def save_movimiento_offline(data: dict):
        """Guarda un movimiento para sync posterior"""
        from datetime import datetime
        data["fecha_movimiento"] = datetime.now().isoformat()
        data["sincronizado"] = False
        
        cache_key = "pending_movimientos"
        pending = get_cache_any_age(cache_key) or []
        pending.append(data)
        set_cache(cache_key, pending, ttl_seconds=86400)
        
        print(f"[OFFLINE] Movimiento guardado: {data.get('tipo')} - {data.get('cantidad')} unidades")
        
        # Intentar sync inmediato si hay conexión
        sync = get_sync_manager()
        if sync and sync.check_connection():
            try:
                from sqlalchemy import text
                with sync.engine.connect() as conn:
                    cols = ", ".join(data.keys())
                    vals = ", ".join([f":{k}" for k in data.keys()])
                    sql = text(f"INSERT INTO movimientos ({cols}) VALUES ({vals})")
                    conn.execute(sql, data)
                    conn.commit()
                    
                    # Quitar del cache
                    pending.pop()
                    set_cache(cache_key, pending, ttl_seconds=86400)
                    print("[OFFLINE] Movimiento syncado inmediatamente")
                    return True
            except Exception as e:
                print(f"[OFFLINE] Error al syncar: {e}")
        
        return False

def get_pending_movimientos():
    """Obtiene movimientos pendientes"""
    return get_cache_any_age("pending_movimientos") or []

_sync_manager = None

def init_sync_manager(engine):
    global _sync_manager
    _sync_manager = SyncManager(engine)
    return _sync_manager

def get_sync_manager():
    return _sync_manager