"""
Sincronización con Supabase - maneja conexión y offline
"""
import threading
import time
from datetime import datetime
from .cache import (
    get_cache, set_cache, get_cache_any_age,
    add_pending_sync, get_pending_sync, clear_pending_sync,
    set_last_sync, get_last_sync
)

class SyncManager:
    def __init__(self, supabase_client):
        self.supabase = supabase_client
        self.is_online = True
        self.sync_thread = None
        self._stop_sync = threading.Event()
    
    def check_connection(self) -> bool:
        """Verifica si hay conexión a internet"""
        try:
            self.supabase.table("productos").select("id").limit(1).execute()
            self.is_online = True
            return True
        except Exception as e:
            print(f"Sin conexión: {e}")
            self.is_online = False
            return False
    
    def sync_pending_changes(self) -> bool:
        """Sincroniza cambios pendientes con Supabase"""
        if not self.check_connection():
            return False
        
        pending = get_pending_sync()
        if not pending:
            return True
        
        synced_ids = []
        
        for item in pending:
            try:
                if item['action'] == 'INSERT':
                    self._sync_insert(item)
                elif item['action'] == 'UPDATE':
                    self._sync_update(item)
                elif item['action'] == 'DELETE':
                    self._sync_delete(item)
                synced_ids.append(item['id'])
            except Exception as e:
                print(f"Error sync {item['action']}: {e}")
        
        if synced_ids:
            clear_pending_sync(synced_ids)
        
        return True
    
    def _sync_insert(self, item):
        import json
        table = item['table_name']
        data = json.loads(item['data']) if item['data'] else {}
        self.supabase.table(table).insert(data).execute()
    
    def _sync_update(self, item):
        import json
        table = item['table_name']
        data = json.loads(item['data']) if item['data'] else {}
        record_id = item['record_id']
        self.supabase.table(table).update(data).eq("id", record_id).execute()
    
    def _sync_delete(self, item):
        table = item['table_name']
        record_id = item['record_id']
        self.supabase.table(table).delete().eq("id", record_id).execute()
    
    def start_background_sync(self, interval_seconds: int = 30):
        """Inicia sincronización en segundo plano"""
        if self.sync_thread and self.sync_thread.is_alive():
            return
        
        self._stop_sync.clear()
        self.sync_thread = threading.Thread(
            target=self._background_sync_loop,
            args=(interval_seconds,),
            daemon=True
        )
        self.sync_thread.start()
    
    def stop_background_sync(self):
        """Detiene sincronización en segundo plano"""
        self._stop_sync.set()
        if self.sync_thread:
            self.sync_thread.join(timeout=2)
    
    def _background_sync_loop(self, interval):
        while not self._stop_sync.is_set():
            self.sync_pending_changes()
            self._stop_sync.wait(interval)
    
    def save_with_offline_support(self, table: str, data: dict, record_id: int = None, action: str = 'INSERT'):
        """Guarda datos - primero local, luego intenta sync"""
        import json
        
        cache_key = f"list_{table}"
        cached = get_cache_any_age(cache_key)
        
        if cached:
            if action == 'INSERT' and record_id is None:
                cached.insert(0, data)
            elif action == 'UPDATE' and record_id:
                cached = [data if str(item.get('id')) == str(record_id) else item for item in cached]
            elif action == 'DELETE' and record_id:
                cached = [item for item in cached if str(item.get('id')) != str(record_id)]
            set_cache(cache_key, cached, ttl_seconds=86400)
        
        if self.check_connection():
            try:
                if action == 'INSERT':
                    result = self.supabase.table(table).insert(data).execute()
                    if hasattr(result, 'data') and result.data:
                        add_pending_sync(table, result.data[0].get('id'), 'INSERT', data)
                elif action == 'UPDATE':
                    self.supabase.table(table).update(data).eq("id", record_id).execute()
                elif action == 'DELETE':
                    self.supabase.table(table).delete().eq("id", record_id).execute()
                return True
            except Exception as e:
                print(f"Error guardando en Supabase: {e}")
                add_pending_sync(table, record_id, action, data)
                return False
        else:
            add_pending_sync(table, record_id, action, data)
            return False

_sync_manager = None

def init_sync_manager(supabase_client):
    global _sync_manager
    _sync_manager = SyncManager(supabase_client)
    return _sync_manager

def get_sync_manager():
    return _sync_manager
