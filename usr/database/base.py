"""
Base de datos - SQLite como única fuente de verdad.
El sistema ahora funciona offline-first con SQLite local.
"""
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, declarative_base
from config.config import get_settings

_base = None
_local_engine = None
_local_session_local = None

def get_base():
    global _base
    if _base is None:
        _base = declarative_base()
    return _base

def get_local_engine():
    """Obtiene el motor de la base de datos local SQLite."""
    global _local_engine
    if _local_engine is None:
        settings = get_settings()
        _local_engine = create_engine(settings.LOCAL_DATABASE_URL, future=True)
    return _local_engine

def get_session():
    """Obtiene sessionmaker para SQLite local."""
    global _local_session_local
    if _local_session_local is None:
        _local_session_local = sessionmaker(bind=get_local_engine(), autoflush=False, autocommit=False)
    return _local_session_local

def get_db():
    """Generator que proporciona una sesión SQLite local.
    Esta es la única fuente de verdad."""
    db = get_session()()
    try:
        yield db
    finally:
        db.close()

def get_db_adaptive():
    """Alias de get_db() - siempre usa SQLite local."""
    return get_db()

# Alias de compatibilidad para código existente
def get_engine():
    """Alias de get_local_engine() para compatibilidad."""
    return get_local_engine()

def get_session_local():
    """Alias de get_session() para compatibilidad."""
    return get_session()

def get_local_session():
    """Alias de get_session() para compatibilidad."""
    return get_session()

def get_local_db():
    """Alias de get_session() para compatibilidad."""
    return get_session()

def check_connection() -> bool:
    """Verifica si hay conexión a internet (solo para indicador visual).
    No bloquea operaciones - SQLite siempre está disponible."""
    import socket
    try:
        socket.create_connection(('8.8.8.8', 53), timeout=3)
        return True
    except:
        return False

def is_online() -> bool:
    """Alias de check_connection() para compatibilidad."""
    return check_connection()

Base = get_base()

def init_local_tables():
    """Inicializa las tablas en la base de datos local."""
    from .local_replica import LocalReplica
    from .sync_queue import SyncQueue
    LocalReplica.create_tables()
    SyncQueue.init_queue()

def get_connection_status() -> dict:
    """Retorna el estado de conexión (solo para indicador)."""
    online = check_connection()
    from .sync_queue import get_sync_queue
    queue = get_sync_queue()
    queue_status = queue.get_status()
    
    return {
        "online": online,
        "is_online": online,
        "pending_uploads": queue_status.get('pending', 0),
        "last_sync": queue_status.get('last_sync')
    }