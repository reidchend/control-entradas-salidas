"""
Sincronización Bidireccional con SQLAlchemy - maneja conexión y offline para multi-dispositivo
Implementa estrategia de sumatoria de movimientos para resolver conflictos.
"""
import threading
import time
from datetime import datetime
from typing import Optional, List, Dict
from sqlalchemy import text
from config.config import get_settings

class SyncManager:
    def __init__(self, engine_getter):
        self._engine_getter = engine_getter
        self._session_local_getter = None
        self.is_online = False
        self._on_connection_change = None
        self._sync_thread = None
        self._stop_event = threading.Event()
        self._background_sync_enabled = False
        
    @property
    def engine(self):
        return self._engine_getter()
    
    def set_session_local_getter(self, session_getter):
        self._session_local_getter = session_getter
    
    def _get_session_maker(self):
        if self._session_local_getter:
            return self._session_local_getter()
        return None
    
    def check_connection(self) -> bool:
        """Verifica si hay conexión a la base de datos remota."""
        try:
            engine = self._engine_getter()
            if engine:
                with engine.connect() as conn:
                    conn.execute(text("SELECT 1"))
                if not self.is_online and self._on_connection_change:
                    self._on_connection_change(True)
                self.is_online = True
                return True
        except Exception as e:
            pass
        
        if self.is_online and self._on_connection_change:
            self._on_connection_change(False)
        self.is_online = False
        return False
    
    def set_connection_callback(self, callback):
        self._on_connection_change = callback
    
    def full_sync(self) -> bool:
        """Realiza una sincronización completa: sube pendientes y descarga del servidor."""
        from .local_replica import LocalReplica
        
        if not self.check_connection():
            print("[SYNC] Sin conexión, usando datos locales")
            return False
        
        print("[SYNC] Iniciando sincronización completa...")
        
        session_maker = self._get_session_maker()
        if not session_maker:
            print("[SYNC] No hay session maker configurado")
            return False
        
        try:
            uploaded = self._upload_pending_movimientos(session_maker)
            
            if uploaded > 0:
                self._download_all_from_server(session_maker)
            else:
                print("[SYNC] No hay pendientes, descargando del servidor...")
                self._download_all_from_server(session_maker)
            
            LocalReplica.set_last_sync("full_sync", datetime.now().isoformat())
            print("[SYNC] Sincronización completa finalizada")
            return True
        except Exception as e:
            print(f"[SYNC] Error en sincronización: {e}")
            return False
    
    def _upload_pending_movimientos(self, session_maker) -> int:
        """Sube los movimientos pendientes al servidor."""
        from .local_replica import LocalReplica
        
        pending_movimientos = LocalReplica.get_movimientos_pendientes()
        if not pending_movimientos:
            print("[SYNC] No hay movimientos pendientes")
            return 0
        
        synced_count = 0
        
        with session_maker() as db:
            for mov in pending_movimientos:
                try:
                    mov_data = {
                        'producto_id': mov.get('producto_id'),
                        'factura_id': mov.get('factura_id'),
                        'tipo': mov.get('tipo'),
                        'cantidad': mov.get('cantidad'),
                        'cantidad_anterior': mov.get('cantidad_anterior', 0),
                        'cantidad_nueva': mov.get('cantidad_nueva', 0),
                        'peso_total': mov.get('peso_total', 0),
                        'peso_registrado': mov.get('peso_registrado'),
                        'foto_peso_url': mov.get('foto_peso_url'),
                        'registrado_por': mov.get('registrado_por'),
                        'observaciones': mov.get('observaciones'),
                        'almacen': mov.get('almacen'),
                        'fecha_movimiento': mov.get('fecha_movimiento'),
                    }
                    
                    columns = ", ".join(mov_data.keys())
                    placeholders = ", ".join([f":{k}" for k in mov_data.keys()])
                    stmt = text(f"INSERT INTO movimientos ({columns}) VALUES ({placeholders})")
                    db.execute(stmt, mov_data)
                    db.commit()
                    
                    LocalReplica.mark_movimiento_sincronizado(mov.get('id'))
                    synced_count += 1
                    print(f"[SYNC] Movimiento {mov.get('id')} syncado")
                except Exception as e:
                    print(f"[SYNC] Error al subir movimiento {mov.get('id')}: {e}")
        
        print(f"[SYNC] {synced_count} movimientos subidos al servidor")
        return synced_count
    
    def _download_all_from_server(self, session_maker) -> bool:
        """Descarga todos los datos del servidor y guarda en local."""
        from .local_replica import LocalReplica
        import json
        from datetime import datetime
        
        def serialize_value(val):
            """Convierte valores a formato serializable."""
            if val is None:
                return None
            if isinstance(val, datetime):
                return val.isoformat()
            if isinstance(val, (int, float, str, bool)):
                return val
            return str(val)
        
        def dict_to_serializable(row_dict):
            """Convierte un diccionario con valores complejos a serializables."""
            return {k: serialize_value(v) for k, v in row_dict.items()}
        
        tables_to_sync = [
            'categorias', 'productos', 'existencias', 
            'movimientos', 'facturas', 'requisiciones'
        ]
        
        with session_maker() as db:
            for table in tables_to_sync:
                try:
                    result = db.execute(text(f"SELECT * FROM {table}"))
                    rows = result.fetchall()
                    data = [dict_to_serializable(dict(row._mapping)) for row in rows]
                    
                    if table == 'categorias':
                        LocalReplica.save_categorias(data)
                    elif table == 'productos':
                        LocalReplica.save_productos(data)
                    elif table == 'existencias':
                        LocalReplica.save_existencias(data)
                    elif table == 'movimientos':
                        LocalReplica.save_movimientos(data)
                    elif table == 'facturas':
                        LocalReplica.save_facturas(data)
                    elif table == 'requisiciones':
                        LocalReplica.save_requisiciones(data)
                    
                    print(f"[SYNC] {len(data)} registros de {table} descargados")
                except Exception as e:
                    print(f"[SYNC] Error descargando {table}: {e}")
        
        print("[SYNC] Descarga completada")
        return True
    
    def start_background_sync(self, session_getter, interval_seconds: int = 20):
        """Inicia sincronización en segundo plano cada interval_seconds."""
        if self._sync_thread and self._sync_thread.is_alive():
            return
        
        self._session_local_getter = session_getter
        self._stop_event.clear()
        self._background_sync_enabled = True
        self._sync_thread = threading.Thread(
            target=self._background_sync_loop,
            args=(interval_seconds,),
            daemon=True
        )
        self._sync_thread.start()
        print(f"[SYNC] Sync en segundo plano iniciado (intervalo: {interval_seconds}s)")
    
    def stop_background_sync(self):
        self._stop_event.set()
        self._background_sync_enabled = False
        if self._sync_thread:
            self._sync_thread.join(timeout=2)
        print("[SYNC] Sync en segundo plano detenido")
    
    def _background_sync_loop(self, interval):
        """Loop de sync en background."""
        while not self._stop_event.is_set():
            try:
                if self.check_connection():
                    self._process_sync_queue()
            except Exception as e:
                print(f"[SYNC] Error en loop: {e}")
            
            self._stop_event.wait(interval)
    
    def _process_sync_queue(self):
        """Procesa la cola de sync - sube pendientes y descarga cambios."""
        from .sync_queue import get_sync_queue
        from .local_replica import LocalReplica
        
        queue = get_sync_queue()
        
        pending = queue.get_pending()
        
        if pending:
            session_maker = self._get_session_maker()
            if session_maker:
                uploaded = self._upload_pending_queue(session_maker, pending)
                print(f"[SYNC] {uploaded} operaciones subidas")
        
        LocalReplica.recalculate_existencias()
        queue.set_last_sync(datetime.now().isoformat())
        print("[SYNC] Ciclo de sync completado")
    
    def _upload_pending_queue(self, session_maker, pending_items) -> int:
        """Sube elementos de la cola a Supabase."""
        from .sync_queue import get_sync_queue
        
        queue = get_sync_queue()
        uploaded = 0
        
        with session_maker() as db:
            for item in pending_items:
                try:
                    data = eval(item['data'])
                    table = item['table_name']
                    operation = item['operation']
                    
                    if table == 'movimientos' and operation == 'insert':
                        mov_clean = {k: v for k, v in data.items() 
                                   if k not in ('sincronizado', 'created_at')}
                        cols = ", ".join(mov_clean.keys())
                        vals = ", ".join([f":{k}" for k in mov_clean.keys()])
                        sql = text(f"INSERT INTO movimientos ({cols}) VALUES ({vals})")
                        db.execute(sql, mov_clean)
                        db.commit()
                        queue.mark_completed(item['id'])
                        uploaded += 1
                        
                except Exception as e:
                    queue.mark_failed(item['id'], str(e))
                    print(f"[SYNC] Error subiendo {table}: {e}")
        
        return uploaded
    
    def get_connection_status(self) -> dict:
        """Estado de conexión y sincronización."""
        from .local_replica import LocalReplica, get_local_conn
        
        pending_count = LocalReplica.get_pending_count()
        last_sync = LocalReplica.get_last_sync("full_sync")
        
        return {
            "online": self.is_online,
            "pending_count": pending_count,
            "last_sync": last_sync,
            "background_enabled": self._background_sync_enabled
        }
    
    def force_sync_now(self) -> bool:
        """Fuerza una sincronización inmediata."""
        return self.full_sync()


def save_movimiento_with_sync(movimiento_data: dict, update_local: bool = True) -> bool:
    """
    Guarda un movimiento en local y opcionalmente lo sincroniza.
    Retorna True si se guardó localmente.
    """
    from datetime import datetime
    from .local_replica import LocalReplica
    from .base import is_online, get_session_local
    
    movimiento_data['fecha_movimiento'] = datetime.now().isoformat()
    movimiento_data['created_at'] = datetime.now().isoformat()
    movimiento_data['sincronizado'] = False
    
    local_id = LocalReplica.save_movimiento(movimiento_data)
    print(f"[OFFLINE] Movimiento guardado localmente con ID: {local_id}")
    
    sync_mgr = get_sync_manager()
    if sync_mgr and sync_mgr.check_connection():
        try:
            session_maker = get_session_local()
            with session_maker() as db:
                mov_clean = {k: v for k, v in movimiento_data.items() 
                           if k not in ('sincronizado', 'created_at')}
                cols = ", ".join(mov_clean.keys())
                vals = ", ".join([f":{k}" for k in mov_clean.keys()])
                sql = text(f"INSERT INTO movimientos ({cols}) VALUES ({vals})")
                db.execute(sql, mov_clean)
                db.commit()
                LocalReplica.mark_movimiento_sincronizado(local_id)
                print("[OFFLINE] Movimiento sincronizado inmediatamente")
                return True
        except Exception as e:
            print(f"[OFFLINE] Error al syncar inmediatamente: {e}")
    
    return False


def recalculate_local_stock():
    """Recalcula las existencias locales desde los movimientos."""
    from .local_replica import LocalReplica
    LocalReplica.recalculate_existencias()


def get_pending_movimientos_count() -> int:
    """Obtiene el número de movimientos pendientes de sincronización."""
    from .local_replica import LocalReplica
    return len(LocalReplica.get_movimientos_pendientes())


_sync_manager: Optional[SyncManager] = None

def init_sync_manager(engine_getter) -> SyncManager:
    global _sync_manager
    _sync_manager = SyncManager(engine_getter)
    return _sync_manager

def get_sync_manager() -> Optional[SyncManager]:
    return _sync_manager
