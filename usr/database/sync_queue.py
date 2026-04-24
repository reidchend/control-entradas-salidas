"""
Cola de sincronización unificada para trabajo offline-first.
Maneja:
- Cola de operaciones pendientes de subir a Supabase
- Metadatos de última sincronización por tabla
- Cache de productos y categorías localmente
"""
import threading
import time
import json
from datetime import datetime
from typing import List, Dict, Optional
from usr.database.conn import get_local_conn, get_cache_conn

class SyncQueue:
    """Maneja la cola de sincronización."""
    
    _instance = None
    _lock = threading.Lock()
    _running = False
    _thread = None
    _stop_event = threading.Event()
    
    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
        return cls._instance
    
    @staticmethod
    def init_queue():
        """Inicializa la tabla de cola."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS sync_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                table_name TEXT NOT NULL,
                operation TEXT NOT NULL,
                data TEXT NOT NULL,
                created_at TEXT NOT NULL,
                retries INTEGER DEFAULT 0,
                last_error TEXT,
                status TEXT DEFAULT 'pending'
            )
        """)
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS sync_metadata (
                key TEXT PRIMARY KEY,
                value TEXT,
                updated_at TEXT
            )
        """)
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def add_pending(table_name: str, operation: str, data: dict) -> int:
        """Agrega una operación a la cola de sync."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT INTO sync_queue (table_name, operation, data, created_at, status)
            VALUES (?, ?, ?, ?, 'pending')
        """, (
            table_name,
            operation,
            json.dumps(data),  # Usar JSON en lugar de str
            datetime.now().isoformat()
        ))
        
        conn.commit()
        row_id = cursor.lastrowid
        conn.close()
        
        return row_id
    
    @staticmethod
    def get_pending(limit: int = 50) -> List[Dict]:
        """Obtiene operaciones pendientes."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT * FROM sync_queue 
            WHERE status = 'pending' 
            ORDER BY created_at 
            LIMIT ?
        """, (limit,))
        
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    @staticmethod
    def mark_completed(queue_id: int) -> None:
        """Marca operación como completada."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            UPDATE sync_queue 
            SET status = 'completed' 
            WHERE id = ?
        """, (queue_id,))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def mark_failed(queue_id: int, error: str) -> None:
        """Marca operación como fallida."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            UPDATE sync_queue 
            SET status = 'failed', last_error = ?, retries = retries + 1
            WHERE id = ?
        """, (error, queue_id,))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_status() -> dict:
        """Obtiene estado de la cola."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT status, COUNT(*) as count 
            FROM sync_queue 
            GROUP BY status
        """)
        
        rows = cursor.fetchall()
        status_dict = {row['status']: row['count'] for row in rows}
        
        cursor.execute("SELECT value FROM sync_metadata WHERE key = 'last_sync'")
        row = cursor.fetchone()
        last_sync = row['value'] if row else None
        
        conn.close()
        
        return {
            'pending': status_dict.get('pending', 0),
            'completed': status_dict.get('completed', 0),
            'failed': status_dict.get('failed', 0),
            'last_sync': last_sync
        }
    
    @staticmethod
    def set_last_sync(timestamp: str) -> None:
        """Guarda timestamp del último sync."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT OR REPLACE INTO sync_metadata (key, value, updated_at)
            VALUES ('last_sync', ?, ?)
        """, (timestamp, datetime.now().isoformat()))
        
        conn.commit()
        conn.close()
    
    @staticmethod
    def get_last_sync() -> Optional[str]:
        """Obtiene timestamp del último sync."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT value FROM sync_metadata WHERE key = 'last_sync'
        """)
        
        row = cursor.fetchone()
        conn.close()
        
        return row['value'] if row else None
    
    @staticmethod
    def cleanup_completed(max_age_hours: int = 24) -> None:
        """Limpia operaciones completadas antiguas."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            DELETE FROM sync_queue 
            WHERE status = 'completed' 
            AND created_at < datetime('now', '-' || ? || ' hours')
        """, (max_age_hours,))
        
        deleted = cursor.rowcount
        conn.commit()
        conn.close()
        
        if deleted > 0:
            print(f"[CLEANUP] {deleted} operaciones antiguas eliminadas")
    
    @staticmethod
    def get_queue_count() -> int:
        """Obtiene número de operaciones pendientes."""
        conn = get_local_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT COUNT(*) as count 
            FROM sync_queue 
            WHERE status = 'pending'
        """)
        
        row = cursor.fetchone()
        conn.close()
        
        return row['count'] if row else 0


def get_sync_queue() -> SyncQueue:
    """Obtiene instancia singleton de SyncQueue."""
    return SyncQueue()


def init_sync_storage():
    """Inicializa storage unificado de sincronización."""
    conn = get_cache_conn()
    cursor = conn.cursor()
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS sync_pending (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            operation TEXT NOT NULL,
            record_id INTEGER,
            data TEXT,
            created_at TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            last_error TEXT,
            retries INTEGER DEFAULT 0
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS sync_metadata (
            key TEXT PRIMARY KEY,
            value TEXT,
            synced_at TEXT
        )
    """)
    
    conn.commit()
    conn.close()


def add_pending_sync(table_name: str, operation: str, record_id: int = None, data: dict = None):
    """Agrega operación pendiente de sincronización (unificada)."""
    conn = get_cache_conn()
    cursor = conn.cursor()
    
    cursor.execute("""
        INSERT INTO sync_pending (table_name, operation, record_id, data, created_at, status)
        VALUES (?, ?, ?, ?, ?, 'pending')
    """, (
        table_name,
        operation,
        record_id,
        json.dumps(data, default=str) if data else None,
        datetime.now().isoformat()
    ))
    
    conn.commit()
    conn.close()


def get_pending_sync(limit: int = 50) -> List[Dict]:
    """Obtiene operaciones pendientes de sync."""
    conn = get_cache_conn()
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT * FROM sync_pending 
        WHERE status = 'pending' 
        ORDER BY created_at 
        LIMIT ?
    """, (limit,))
    
    rows = cursor.fetchall()
    conn.close()
    
    return [dict(row) for row in rows]


def mark_sync_complete(ids: List[int]) -> None:
    """Marca operaciones como completadas."""
    if not ids:
        return
    
    conn = get_cache_conn()
    cursor = conn.cursor()
    placeholders = ','.join('?' * len(ids))
    cursor.execute(f"UPDATE sync_pending SET status = 'completed' WHERE id IN ({placeholders})", ids)
    conn.commit()
    conn.close()


def clear_pending_sync(ids: List[int]) -> None:
    """Elimina operaciones sincronizadas."""
    if not ids:
        return
    
    conn = get_cache_conn()
    cursor = conn.cursor()
    placeholders = ','.join('?' * len(ids))
    cursor.execute(f"DELETE FROM sync_pending WHERE id IN ({placeholders})", ids)
    conn.commit()
    conn.close()


def clear_all_pending_sync():
    """Elimina todas las operaciones pendientes."""
    conn = get_cache_conn()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM sync_pending")
    conn.commit()
    conn.close()


def set_last_sync(key: str, timestamp: str = None) -> None:
    """Guarda timestamp de última sincronización."""
    if timestamp is None:
        timestamp = datetime.now().isoformat()
    
    conn = get_cache_conn()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT OR REPLACE INTO sync_metadata (key, synced_at) VALUES (?, ?)",
        (key, timestamp)
    )
    conn.commit()
    conn.close()


def get_last_sync(key: str) -> Optional[str]:
    """Obtiene timestamp de última sincronización."""
    conn = get_cache_conn()
    cursor = conn.cursor()
    cursor.execute("SELECT synced_at FROM sync_metadata WHERE key = ?", (key,))
    row = cursor.fetchone()
    conn.close()
    
    return row['synced_at'] if row else None


init_sync_storage()