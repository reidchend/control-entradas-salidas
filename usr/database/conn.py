import os, sqlite3
from pathlib import Path

_db_path: str | None = None

# Cache path - usar directorio actual que es escribible en Android
_cache_dir = Path(".")
_cache_db_path = _cache_dir / ".control_cache.db"
_cache_db_path.parent.mkdir(exist_ok=True)

def set_db_path(path: str) -> None:
    """Llamar desde main() antes de cualquier import de BD."""
    global _db_path
    _db_path = path
    parent = Path(path).parent
    try:
        parent.mkdir(parents=True, exist_ok=True)
    except PermissionError:
        # En Android, guardar junto al script si falla
        pass

def get_db_path() -> str:
    if _db_path is None:
        raise RuntimeError(
            "DB path no inicializado. "
            "Llama set_db_path() en main() primero."
        )
    return _db_path

def get_local_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(get_db_path())
    conn.row_factory = sqlite3.Row
    return conn

def get_cache_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(str(_cache_db_path))
    conn.row_factory = sqlite3.Row
    return conn