import os, sqlite3
from pathlib import Path

_db_path: str | None = None

# Cache path
_cache_dir = Path("./.control_entradas_cache")
try:
    _cache_dir.mkdir(exist_ok=True)
except:
    _cache_dir = Path("./cache")
    _cache_dir.mkdir(exist_ok=True)
_cache_db_path = _cache_dir / "cache.db"

def set_db_path(path: str) -> None:
    """Llamar desde main() antes de cualquier import de BD."""
    global _db_path
    _db_path = path
    Path(path).parent.mkdir(parents=True, exist_ok=True)

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