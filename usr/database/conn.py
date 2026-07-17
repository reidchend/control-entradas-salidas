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
    
    os.environ['LYCORIS_DB_PATH'] = path

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
    env_path = os.environ.get('LYCORIS_DB_PATH')
    if env_path:
        return env_path
    if _db_path is None:
        try:
            conn_dir = os.path.dirname(os.path.abspath(__file__))
            # conn.py está en <root>/usr/database/conn.py
            # o en <root>/app_updates/usr/database/conn.py
            candidate = os.path.dirname(os.path.dirname(conn_dir))  # <root>/usr  o  <root>/app_updates
            # Si el padre del candidato también contiene 'usr', es porque
            # estamos dentro de app_updates/ y debemos usar el padre como raíz
            parent = os.path.dirname(candidate)
            if os.path.exists(os.path.join(parent, 'usr')):
                candidate = parent
            return os.path.join(candidate, "lycoris_local.db")
        except Exception:
            return str(Path(".") / "lycoris_local.db")
    return _db_path

def get_local_conn() -> sqlite3.Connection:
    db_path = get_db_path()
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        return conn
    except sqlite3.OperationalError:
        # Si falla, intentamos la ruta relativa como último recurso
        fallback_path = str(Path(".") / "lycoris_local.db")
        conn = sqlite3.connect(fallback_path)
        conn.row_factory = sqlite3.Row
        return conn

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