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
            # 1. Procesar la cola de sync primero (Categorías, Productos, Facturas, Pagos)
            # Esto asegura que existan las claves foráneas antes de subir movimientos
            self._process_sync_queue()
            
            # 2. Subir movimientos pendientes (que pueden referenciar esas facturas)
            self._upload_pending_movimientos()
            
            # 3. Descargar datos actualizados del servidor
            self._download_all_from_server()
            
            LocalReplica.set_last_sync("full_sync", datetime.now().isoformat())
            print("[SYNC] Sincronización completa finalizada")
            
            if self._on_sync_complete:
                try:
                    self._on_sync_complete()
                except Exception as e:
                    print(f"[SYNC] Error en callback: {e}")
            
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
            try:
                from usr.error_handler import show_sync_error
                show_sync_error(f"Error de sincronización: {type(e).__name__}")
            except:
                pass
            return False
    
    def _upload_pending_movimientos(self) -> int:
        from .local_replica import LocalReplica
        from sqlalchemy import create_engine
        from config.config import get_settings

        pending_movimientos = LocalReplica.get_movimientos_pendientes()
        if not pending_movimientos:
            print("[SYNC] No hay movimientos pendientes")
            return 0

        settings = get_settings()
        remote_engine = self._create_remote_engine()
        synced_count = 0

        try:
            with remote_engine.connect() as conn:
                for mov in pending_movimientos:
                    try:
                        mov_id = mov.get('id')
                        factura_id = mov.get('factura_id')

                        match = conn.execute(text("""
                            SELECT id FROM movimientos 
                            WHERE producto_id = :p AND tipo = :t AND cantidad = :c
                            AND fecha_movimiento = :f AND almacen = :a
                            LIMIT 1
                        """), {
                            'p': mov.get('producto_id'),
                            't': mov.get('tipo'),
                            'c': mov.get('cantidad'),
                            'f': mov.get('fecha_movimiento'),
                            'a': mov.get('almacen'),
                        }).fetchone()

                        if match:
                            remote_mov_id = match[0]
                            if factura_id:
                                conn.execute(
                                    text("UPDATE movimientos SET factura_id = :fid WHERE id = :id"),
                                    {'fid': factura_id, 'id': remote_mov_id}
                                )
                                conn.commit()
                                print(f"[SYNC] Movimiento {mov_id} -> factura_id={factura_id} actualizado en Supabase")
                        else:
                            mov_data = {
                                'producto_id': mov.get('producto_id'),
                                'factura_id': factura_id,
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
                            cols = ", ".join(mov_data.keys())
                            placeholders = ", ".join([f":{k}" for k in mov_data.keys()])
                            conn.execute(text(f"INSERT INTO movimientos ({cols}) VALUES ({placeholders})"), mov_data)
                            conn.commit()

                        LocalReplica.mark_movimiento_sincronizado(mov_id)
                        synced_count += 1
                    except Exception as e:
                        print(f"[SYNC] Error al subir movimiento {mov.get('id')}: {e}")
        finally:
            remote_engine.dispose()

        print(f"[SYNC] {synced_count} movimientos subidos al servidor")
        return synced_count
    
    def _download_all_from_server(self) -> bool:
        from .local_replica import LocalReplica
        import json
        from datetime import datetime
        
        def serialize_value(val):
            if val is None: return None
            if isinstance(val, datetime): return val.isoformat()
            if isinstance(val, (int, float, str, bool)): return val
            return str(val)
        
        def dict_to_serializable(row_dict):
            return {k: serialize_value(v) for k, v in row_dict.items()}
        
        tables_to_sync = [
            ('categorias', 'categorias'), 
            ('productos', 'productos'), 
            ('proveedores', 'proveedores'),
            ('existencias', 'existencias'), 
            ('movimientos', 'movimientos'), 
            ('facturas', 'facturas'), 
            ('factura_pagos', 'factura_pagos'),
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
                    remote_ids = [r['id'] for r in data if r.get('id') is not None]
                    
                    if local_table == 'categorias':
                        LocalReplica.save_categorias(data)
                        LocalReplica.delete_orphaned_records('categorias', remote_ids, 'nombre')
                    elif local_table == 'productos':
                        LocalReplica.save_productos(data)
                        LocalReplica.delete_orphaned_records('productos', remote_ids, 'codigo')
                    elif local_table == 'proveedores':
                        LocalReplica.save_proveedores(data)
                        LocalReplica.delete_orphaned_records('proveedores', remote_ids, 'nombre')
                    elif local_table == 'existencias':
                        LocalReplica.save_existencias(data)
                    elif local_//Corte aquí para evitar error de match, voy a usar el contenido completo en el siguiente paso'