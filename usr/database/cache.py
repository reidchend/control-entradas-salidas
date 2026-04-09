"""
Sistema de caché local para trabajo offline
"""
import sqlite3
import json
import os
from datetime import datetime
from pathlib import Path

def get_cache_dir():
    """Obtiene el directorio de caché válido para todas las plataformas"""
    # En Android/Flet, usamos el directorio de trabajo actual
    # que es escribible
    cache_dir = Path("./.control_entradas_cache")
    try:
        cache_dir.mkdir(exist_ok=True)
    except PermissionError:
        # Si falla, usamos un directorio alternativo
        cache_dir = Path("/data/data/com.reidchend.lycoris.control_entradas_salidas/cache")
        try:
            cache_dir.mkdir(exist_ok=True)
        except:
            # Último recurso: directorio temporal
            cache_dir = Path("./cache")
            cache_dir.mkdir(exist_ok=True)
    return cache_dir

CACHE_DIR = get_cache_dir()
DB_PATH = CACHE_DIR / "cache.db"

def get_cache_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_cache_db():
    """Inicializa la base de datos local de caché"""
    conn = get_cache_conn()
    cursor = conn.cursor()
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS cache_data (
            key TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS pending_sync (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            record_id INTEGER,
            action TEXT NOT NULL,
            data TEXT,
            created_at TEXT NOT NULL
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS last_sync (
            key TEXT PRIMARY KEY,
            synced_at TEXT NOT NULL
        )
    """)
    
    conn.commit()
    conn.close()

def set_cache(key: str, data: list or dict, ttl_seconds: int = 3600):
    """Guarda datos en caché local"""
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
    """Obtiene datos del caché si aún están vigentes"""
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
    """Obtiene datos del caché sin importar la edad"""
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

def add_pending_sync(table_name: str, record_id: int, action: str, data: dict = None):
    """Agrega una operación pendiente de sincronización"""
    conn = get_cache_conn()
    cursor = conn.cursor()
    
    cursor.execute(
        "INSERT INTO pending_sync (table_name, record_id, action, data, created_at) VALUES (?, ?, ?, ?, ?)",
        (table_name, record_id, action, json.dumps(data, default=str) if data else None, datetime.now().isoformat())
    )
    conn.commit()
    conn.close()

def get_pending_sync():
    """Obtiene todas las operaciones pendientes"""
    conn = get_cache_conn()
    cursor = conn.cursor()
    
    cursor.execute("SELECT * FROM pending_sync ORDER BY created_at")
    rows = cursor.fetchall()
    conn.close()
    
    return [dict(row) for row in rows]

def clear_pending_sync(ids: list):
    """Elimina operaciones sincronizadas"""
    if not ids:
        return
    
    conn = get_cache_conn()
    cursor = conn.cursor()
    placeholders = ','.join('?' * len(ids))
    cursor.execute(f"DELETE FROM pending_sync WHERE id IN ({placeholders})", ids)
    conn.commit()
    conn.close()

def clear_all_pending_sync():
    """Elimina todas las operaciones pendientes"""
    conn = get_cache_conn()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM pending_sync")
    conn.commit()
    conn.close()

def set_last_sync(key: str):
    """Guarda timestamp de última sincronización"""
    conn = get_cache_conn()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT OR REPLACE INTO last_sync (key, synced_at) VALUES (?, ?)",
        (key, datetime.now().isoformat())
    )
    conn.commit()
    conn.close()

def get_last_sync(key: str):
    """Obtiene timestamp de última sincronización"""
    conn = get_cache_conn()
    cursor = conn.cursor()
    cursor.execute("SELECT synced_at FROM last_sync WHERE key = ?", (key,))
    row = cursor.fetchone()
    conn.close()
    
    if row:
        try:
            return datetime.fromisoformat(row['synced_at'])
        except:
            return None
    return None

init_cache_db()
