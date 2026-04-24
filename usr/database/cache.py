"""
Sistema de caché local para trabajo offline.
Solo maneja cache de datos (no sync - ese está en sync_queue.py).
"""
import sqlite3
import json
from datetime import datetime
from usr.database.conn import get_cache_conn

def init_cache_db():
    """Inicializa tablas decache (no sync)."""
    conn = get_cache_conn()
    cursor = conn.cursor()
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS cache_data (
            key TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)
    
    conn.commit()
    conn.close()

def set_cache(key: str, data: list or dict, ttl_seconds: int = 3600):
    conn = get_cache_conn()
    cursor = conn.cursor()
    
    if isinstance(data, (list, dict)):
        data = json.dumps(data, default=str)
    
    updated_at = datetime.now().isoformat()
    cursor.execute(
        "INSERT OR REPLACE INTO cache_data (key, data, updated_at) VALUES (?, ?, ?)",
        (key, data, updated_at)
    )
    conn.commit()
    conn.close()

def get_cache(key: str, max_age_seconds: int = 3600):
    conn = get_cache_conn()
    cursor = conn.cursor()
    
    cursor.execute(
        "SELECT data, updated_at FROM cache_data WHERE key = ?",
        (key,)
    )
    row = cursor.fetchone()
    conn.close()
    
    if not row:
        return None
    
    try:
        data_age = (datetime.now() - datetime.fromisoformat(row['updated_at'])).total_seconds()
        if data_age > max_age_seconds:
            return None
        return json.loads(row['data'])
    except:
        return None

def get_cache_any_age(key: str):
    conn = get_cache_conn()
    cursor = conn.cursor()
    
    cursor.execute("SELECT data FROM cache_data WHERE key = ?", (key,))
    row = cursor.fetchone()
    conn.close()
    
    if row:
        try:
            return json.loads(row['data'])
        except:
            return None
    return None

init_cache_db()