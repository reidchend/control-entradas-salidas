import os, sqlite3
from pathlib import Path

_db_path: str | None = None

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