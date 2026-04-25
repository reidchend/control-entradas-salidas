import os, sqlite3
from pathlib import Path

_db_path: str | None = None

# Cache path - usar directorio actual que es escribible en Android
_cache_dir = Path(".")
_cache_db_path = _cache_dir / ".control_cache.db"
try:
    _cache_db_path.parent.mkdir(exist_ok=True)
except:
    pass

def set_db_path(path: str) -> None:
    """Llamar desde main() antes de cualquier import de BD."""
    global _db_path
    
    parent = Path(path).parent
    
    # Intentar crear directorio
    try:
        parent.mkdir(parents=True, exist_ok=True)
    except (PermissionError, OSError):
        # En Android, usar directorio alternativo si falla
        alt_paths = [
            Path("."),
            Path("/data/data/com.reidchend.lycoris.lycoris_control/files"),
            Path("files"),
        ]
        for alt in alt_paths:
            try:
                alt.mkdir(parents=True, exist_ok=True)
                # Modificar path para usar el directorio alternativo
                path = str(alt / Path(path).name)
                break
            except:
                continue
    
    _db_path = path

def get_db_path() -> str:
    if _db_path is None:
        # Fallback si no se inicializó
        return str(Path(".") / "lycoris_local.db")
    return _db_path

def get_local_conn() -> sqlite3.Connection:
    db_path = get_db_path()
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        return conn
    except sqlite3.OperationalError:
        # Fallback: guardar en directorio actual
        fallback_path = str(Path(".") / "lycoris_local.db")
        if db_path != fallback_path:
            global _db_path
            _db_path = fallback_path
            conn = sqlite3.connect(fallback_path)
            conn.row_factory = sqlite3.Row
            return conn
        raise

def get_cache_conn() -> sqlite3.Connection:
    try:
        conn = sqlite3.connect(str(_cache_db_path))
        conn.row_factory = sqlite3.Row
        return conn
    except:
        # Fallback: usar archivo en directorio actual
        fallback = Path(".") / ".control_cache.db"
        conn = sqlite3.connect(str(fallback))
        conn.row_factory = sqlite3.Row
        return conn