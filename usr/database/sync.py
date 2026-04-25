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
        self._on_sync_complete_callbacks = []
        self._on_sync_complete = None  # Callback simple para sync completo
    
    @property
    def engine(self):
        return self._engine_getter()
    
    def set_session_local_getter(self, session_getter):
        self._session_local_getter = session_getter
    
    def set_sync_complete_callback(self, callback):
        """Registra función a llamar cada vez que termina un sync."""
        self._on_sync_complete = callback
    
    def add_sync_callback(self, callback):
        """Registra un callback que se ejecuta cuando termina un sync."""
        if callback not in self._on_sync_complete_callbacks:
            self._on_sync_complete_callbacks.append(callback)
    
    def remove_sync_callback(self, callback):
        """Elimina un callback registrado."""
        if callback in self._on_sync_complete_callbacks:
            self._on_sync_complete_callbacks.remove(callback)
    
    def _notify_sync_complete(self):
        """Notifica a todos los callbacks registrados."""
        for callback in self._on_sync_complete_callbacks:
            try:
                callback()
            except Exception as e:
                print(f"[SYNC] Error en callback: {e}")
    
    def _get_session_maker(self):
        if self._session_local_getter:
            return self._session_local_getter()
        return None
    
    def _get_remote_session_maker(self):
        engine = self._create_remote_engine()
        return engine.connect
    
    def _create_remote_engine(self):
        from sqlalchemy import create_engine
        from config.config import get_settings
        return create_engine(get_settings().DATABASE_URL)
    
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
        
        try:
            # Subir pendientes a Supabase (usar remote session)
            remote_session = self._get_remote_session_maker()
            uploaded = self._upload_pending_movimientos()
            
            # Descargar del servidor
            local_session = self._get_session_maker()
            if uploaded > 0:
                self._download_all_from_server(local_session)
            else:
                print("[SYNC] No hay pendientes, descargando del servidor...")
                self._download_all_from_server(local_session)
            
            LocalReplica.set_last_sync("full_sync", datetime.now().isoformat())
            print("[SYNC] Sincronización completa finalizada")
            
            # Notificar callback
            if self._on_sync_complete:
                try:
                    self._on_sync_complete()
                except Exception as e:
                    print(f"[SYNC] Error en callback: {e}")
            
            # Notificar también al sistema global de vistas
            try:
                from .sync_callbacks import notify_sync_complete as notify_global
                notify_global()
            except Exception as e:
                print(f"[SYNC] Error en notify_global: {e}")
            
            return True
        except Exception as e:
            print(f"[SYNC] Error en sincronización: {e}")
            import traceback
            traceback.print_exc()
            return False
    
    def _upload_pending_movimientos(self) -> int:
        from .local_replica import LocalReplica
        from sqlalchemy import create_engine
        from config.config import get_settings

        pending_movimientos = LocalReplica.get_movimientos_pendientes()
        if not pending_movimientos:
            print("[SYNC] No hay movimientos pendientes")
            return 0

        # Crear engine REMOTO (Supabase), igual que _download_all_from_server
        settings = get_settings()
        remote_engine = self._create_remote_engine()
        synced_count = 0

        try:
            with remote_engine.connect() as conn:
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
                        conn.execute(stmt, mov_data)
                        conn.commit()
                        LocalReplica.mark_movimiento_sincronizado(mov.get('id'))
                        synced_count += 1
                        print(f"[SYNC] Movimiento {mov.get('id')} subido a Supabase")
                    except Exception as e:
                        print(f"[SYNC] Error al subir movimiento {mov.get('id')}: {e}")
        finally:
            remote_engine.dispose()

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
            ('categorias', 'categorias'), 
            ('productos', 'productos'), 
            ('existencias', 'existencias'), 
            ('movimientos', 'movimientos'), 
            ('facturas', 'facturas'), 
            ('requisiciones', 'requisiciones')
        ]
        
        from sqlalchemy import create_engine
        from config.config import get_settings
        settings = get_settings()
        remote_engine = self._create_remote_engine()
        
        with remote_engine.connect() as conn:
            for local_table, server_table in tables_to_sync:
                try:
                    result = conn.execute(text(f"SELECT * FROM {server_table}"))
                    rows = result.fetchall()
                    data = [dict_to_serializable(dict(row._mapping)) for row in rows]
                    
                    if local_table == 'categorias':
                        LocalReplica.clear_categorias()
                        LocalReplica.save_categorias(data)
                    elif local_table == 'productos':
                        LocalReplica.clear_productos()
                        LocalReplica.save_productos(data)
                    elif local_table == 'existencias':
                        LocalReplica.save_existencias(data)
                    elif local_table == 'movimientos':
                        LocalReplica.save_movimientos(data)
                    elif local_table == 'facturas':
                        LocalReplica.save_facturas(data)
                    elif local_table == 'requisiciones':
                        LocalReplica.save_requisiciones(data)
                    
                    print(f"[SYNC] {len(data)} {local_table} baixats")
                except Exception as e:
                    print(f"[SYNC] Error descargando {local_table}: {e}")
        
        remote_engine.dispose()
        
        print("[SYNC] Descarga completada")
        return True
    
    def start_background_sync(self, session_getter, interval_seconds: int = 20):
        """Inicia sincronización en segundo plano cada interval_seconds."""
        print(f"[SYNC] start_background_sync() llamado con interval={interval_seconds}s")
        if self._sync_thread and self._sync_thread.is_alive():
            print("[SYNC] Hilo ya está corriendo, no se inicia nuevo")
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
        from .sync_callbacks import notify_sync_complete as notify_global
        
        while not self._stop_event.is_set():
            try:
                if self.check_connection():
                    # Subir movimientos pendientes (sincronizado=0)
                    self._upload_pending_movimientos()
                    # Subir pendientes de la cola
                    self._process_sync_queue()
                    # Descargar cambios del servidor
                    self._download_all_from_server(self._get_session_maker())
                    self._notify_sync_complete()
                    notify_global()
            except Exception as e:
                print(f"[SYNC] Error en loop: {e}")
            
            self._stop_event.wait(interval)
    
    def _process_sync_queue(self):
        """Procesa la cola de sync - sube pendientes y descarga cambios."""
        from .sync_queue import get_sync_queue
        from .local_replica import LocalReplica
        
        # Verificar conexión antes de procesar
        if not self.check_connection():
            print("[SYNC] Sin conexión, saltando procesamiento de cola")
            return
        
        queue = get_sync_queue()
        
        pending = queue.get_pending()
        
        if pending:
            # Usar conexión a Supabase para subir datos
            from sqlalchemy import create_engine
            from config.config import get_settings
            settings = get_settings()
            remote_engine = self._create_remote_engine()
            
            try:
                uploaded = self._upload_to_remote(remote_engine, pending)
                print(f"[SYNC] {uploaded} operaciones subidas a Supabase")
            except Exception as e:
                print(f"[SYNC] Error al subir a Supabase: {e}")
            finally:
                remote_engine.dispose()
        
        LocalReplica.recalculate_existencias()
        queue.set_last_sync(datetime.now().isoformat())
        print("[SYNC] Ciclo de sync completado")
    
    def _upload_to_remote(self, remote_engine, pending_items) -> int:
        """Sube elementos de la cola a Supabase usando SQL directo."""
        import json
        from .sync_queue import get_sync_queue
        
        queue = get_sync_queue()
        uploaded = 0
        
        with remote_engine.connect() as conn:
            for item in pending_items:
                table = None
                try:
                    data = json.loads(item['data'])
                    table = item['table_name']
                    operation = item['operation']
                    
                    if table == 'categorias':
                        # Determinar si es insert o update
                        has_nombre = 'nombre' in data and data.get('nombre')
                        has_id = 'id' in data and data.get('id')
                        
                        if has_nombre:
                            cols = ['nombre', 'descripcion', 'color', 'activo', 'updated_at']
                            vals = {
                                'nombre': data.get('nombre'),
                                'descripcion': data.get('descripcion', ''),
                                'color': data.get('color', '#888888'),
                                'activo': data.get('activo', 1),
                                'updated_at': data.get('updated_at')
                            }
                            
                            # Upsert por nombre
                            check_sql = text("SELECT id FROM categorias WHERE nombre = :nombre")
                            existing = conn.execute(check_sql, {'nombre': vals['nombre']}).fetchone()
                            
                            if existing:
                                set_cols = ", ".join([f"{k} = :{k}" for k in vals.keys()])
                                sql = text(f"UPDATE categorias SET {set_cols} WHERE nombre = :nombre")
                            else:
                                cols_str = ", ".join(vals.keys())
                                placeholders = ", ".join([f":{k}" for k in vals.keys()])
                                sql = text(f"INSERT INTO categorias ({cols_str}) VALUES ({placeholders})")
                        elif has_id:
                            # Update por ID (ej: desactivar)
                            vals = {
                                'id': data.get('id'),
                                'activo': data.get('activo', 0),
                                'updated_at': data.get('updated_at')
                            }
                            sql = text("UPDATE categorias SET activo = :activo, updated_at = :updated_at WHERE id = :id")
                        else:
                            continue
                        
                        conn.execute(sql, vals)
                        conn.commit()
                        queue.mark_completed(item['id'])
                        uploaded += 1
                        print(f"[SYNC] Categoría sincronizada")
                        
                    elif table == 'productos':
                        # Determinar si es insert o update
                        has_codigo = 'codigo' in data and data.get('codigo')
                        has_id = 'id' in data and data.get('id')
                        
                        vals = None  # Inicializar
                        
                        if has_codigo:
                            vals = {
                                'nombre': data.get('nombre'),
                                'codigo': data.get('codigo'),
                                'descripcion': data.get('descripcion', ''),
                                'categoria_id': int(data.get('categoria_id')) if data.get('categoria_id') else None,
                                'es_pesable': data.get('es_pesable', 0),
                                'requiere_foto_peso': data.get('requiere_foto_peso', 0),
                                'peso_unitario': float(data.get('peso_unitario', 0)),
                                'unidad_medida': data.get('unidad_medida', 'unidad'),
                                'stock_actual': float(data.get('stock_actual', 0)),
                                'stock_minimo': float(data.get('stock_minimo', 0)),
                                'activo': data.get('activo', 1),
                                'almacen_predeterminado': data.get('almacen_predeterminado', 'principal'),
                                'updated_at': data.get('updated_at')
                            }
                            
                            # Upsert por código
                            check_sql = text("SELECT id FROM productos WHERE codigo = :codigo")
                            existing = conn.execute(check_sql, {'codigo': vals['codigo']}).fetchone()
                            
                            if existing:
                                set_cols = ", ".join([f"{k} = :{k}" for k in vals.keys()])
                                sql = text(f"UPDATE productos SET {set_cols} WHERE codigo = :codigo")
                            else:
                                cols_str = ", ".join(vals.keys())
                                placeholders = ", ".join([f":{k}" for k in vals.keys()])
                                sql = text(f"INSERT INTO productos ({cols_str}) VALUES ({placeholders})")
                        elif has_id:
                            # Update por ID (ej: desactivar)
                            vals = {
                                'id': data.get('id'),
                                'activo': data.get('activo', 0),
                                'updated_at': data.get('updated_at')
                            }
                            sql = text("UPDATE productos SET activo = :activo, updated_at = :updated_at WHERE id = :id")
                        else:
                            continue
                        
                        conn.execute(sql, vals)
                        conn.commit()
                        queue.mark_completed(item['id'])
                        uploaded += 1
                        print(f"[SYNC] Producto sincronizado")
                        
                    elif table == 'movimientos' and operation == 'insert':
                        mov_data = {k: v for k, v in data.items() 
                                   if k not in ('sincronizado', 'created_at')}
                        # Quitar ID local para que Supabase genere uno nuevo
                        mov_data.pop('id', None)
                        
                        cols = ", ".join(mov_data.keys())
                        vals = ", ".join([f":{k}" for k in mov_data.keys()])
                        sql = text(f"INSERT INTO movimientos ({cols}) VALUES ({vals})")
                        conn.execute(sql, mov_data)
                        conn.commit()
                        queue.mark_completed(item['id'])
                        uploaded += 1
                        print(f"[SYNC] Movimiento sincronizado")
                    
                    elif table == 'movimientos' and operation == 'delete':
                        # Eliminar movimiento por ID
                        mov_id = data.get('id')
                        if mov_id:
                            conn.execute(text("DELETE FROM movimientos WHERE id = :id"), {"id": mov_id})
                            conn.commit()
                            queue.mark_completed(item['id'])
                            uploaded += 1
                            print(f"[SYNC] Movimiento eliminado en Supabase")
                        
                except Exception as e:
                    queue.mark_failed(item['id'], str(e))
                    print(f"[SYNC] Error subiendo {table}: {e}")
        
        return uploaded
    
    def get_connection_status(self) -> dict:
        """Estado de conexión y sincronización."""
        from .sync_queue import SyncQueue
        
        pending = SyncQueue.get_pending(limit=100)
        last = SyncQueue.get_last_sync()
        
        return {
            "online": self.is_online,
            "pending_count": len(pending),
            "last_sync": last,
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
