from .base import (
    get_engine, get_session_local, get_base, get_db, 
    get_local_engine, get_local_session, get_local_db,
    is_online, check_connection, init_local_tables,
    get_connection_status, get_db_adaptive
)
from .local_replica import LocalReplica
from .sync import (
    SyncManager, init_sync_manager, get_sync_manager,
    save_movimiento_with_sync, recalculate_local_stock,
    get_pending_movimientos_count
)

engine = get_engine()
SessionLocal = get_session_local()
Base = get_base()

__all__ = [
    'Base', 'engine', 'get_db', 'get_db_adaptive', 'SessionLocal', 
    'get_engine', 'get_session_local', 'get_local_engine',
    'get_local_session', 'get_local_db', 'is_online',
    'check_connection', 'init_local_tables', 'get_connection_status',
    'LocalReplica', 'SyncManager', 'init_sync_manager',
    'get_sync_manager', 'save_movimiento_with_sync',
    'recalculate_local_stock', 'get_pending_movimientos_count'
]
