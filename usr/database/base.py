from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, declarative_base
from config.config import get_settings

_base = None
_engine = None
_local_engine = None
_session_local = None
_local_session_local = None
_is_online = True
_online_check_time = 0
_ONLINE_CACHE_TTL = 10

def get_base():
    global _base
    if _base is None:
        _base = declarative_base()
    return _base

def get_engine(force_online: bool = None):
    """Obtiene el motor de base de datos. Intenta online por defecto, fallback a local."""
    global _engine, _is_online
    
    if force_online is not None:
        if force_online:
            _is_online = True
        else:
            _is_online = False
    
    if _engine is None:
        settings = get_settings()
        try:
            _engine = create_engine(
                settings.DATABASE_URL, 
                future=True, 
                pool_timeout=3
            )
            with _engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            _is_online = True
        except Exception as e:
            print(f"[OFFLINE] No hay conexión a Supabase: {e}")
            _engine = None
            _is_online = False
    
    return _engine

def is_online() -> bool:
    """Retorna True si hay conexión a la base de datos remota (con cache de 10 seg)."""
    global _is_online, _engine, _session_local, _online_check_time
    
    import time
    current_time = time.time()
    
    if current_time - _online_check_time < _ONLINE_CACHE_TTL:
        return _is_online
    
    if _is_online and _engine:
        try:
            with _engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            _online_check_time = current_time
            return True
        except Exception as e:
            print(f"[OFFLINE] Conexión perdida: {e}")
            _engine.dispose()
            _is_online = False
            _engine = None
            _session_local = None
            _online_check_time = current_time
    elif _is_online and _engine is None:
        _is_online = False
    
    _online_check_time = current_time
    return _is_online

def get_local_engine():
    """Obtiene el motor de la base de datos local SQLite."""
    global _local_engine
    if _local_engine is None:
        settings = get_settings()
        _local_engine = create_engine(settings.LOCAL_DATABASE_URL, future=True)
    return _local_engine

def get_session_local():
    global _session_local
    if _session_local is None:
        _session_local = sessionmaker(bind=get_engine(), autoflush=False, autocommit=False)
    return _session_local

def get_local_session():
    """Obtiene sessionmaker para la base de datos local."""
    global _local_session_local
    if _local_session_local is None:
        _local_session_local = sessionmaker(bind=get_local_engine(), autoflush=False, autocommit=False)
    return _local_session_local

def get_db():
    """Generator que proporciona una sesión de base de datos."""
    db = get_session_local()()
    try:
        yield db
    finally:
        db.close()

def get_local_db():
    """Generator que proporciona una sesión de base de datos local."""
    db = get_local_session()()
    try:
        yield db
    finally:
        db.close()

def get_db_adaptive():
    """Generator que proporciona una sesión según el estado de conexión.
    Si está online usa Supabase, si está offline usa SQLite local."""
    global _is_online
    
    online = is_online()
    
    if online:
        db = get_session_local()()
        try:
            yield db
        finally:
            db.close()
    else:
        from .local_replica import init_local_db
        init_local_db()
        db = get_local_session()()
        try:
            yield db
        finally:
            db.close()

def engine_connection_test():
    """Prueba la conexión a la base de datos remota."""
    global _is_online
    try:
        engine = get_engine()
        if engine:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            _is_online = True
            return True
    except:
        _is_online = False
    return False

def check_connection() -> bool:
    """Verifica y actualiza el estado de conexión usando caché."""
    return is_online()

Base = get_base()

def init_local_tables():
    """Inicializa las tablas en la base de datos local."""
    from .local_replica import LocalReplica
    LocalReplica.create_tables()

def get_connection_status() -> dict:
    """Retorna el estado de conexión."""
    return {
        "online": is_online(),
        "is_online": is_online()
    }
