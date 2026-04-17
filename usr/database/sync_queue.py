"""
Cola de sincronización para trabajo offline-first.
Maneja la cola de operaciones pendientes de subir a Supabase.
"""
import sqlite3
import threading
import time
from datetime import datetime
from typing import List, Dict, Optional
from config.config import get_settings

LOCAL_DB_PATH = get_settings().LOCAL_DB_PATH

def get_local_conn():
    """Obtiene conexión a la base de datos local."""
    conn = sqlite3.connect(LOCAL_DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

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
            str(data),
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