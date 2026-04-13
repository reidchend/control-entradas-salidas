from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, declarative_base
from config.config import get_settings

_base = None
_engine = None
_session_local = None

def get_base():
    global _base
    if _base is None:
        _base = declarative_base()
    return _base

def get_engine():
    global _engine
    if _engine is None:
        settings = get_settings()
        _engine = create_engine(settings.DATABASE_URL, future=True, pool_pre_ping=True)
    return _engine

def get_session_local():
    global _session_local
    if _session_local is None:
        _session_local = sessionmaker(bind=get_engine(), autoflush=False, autocommit=False)
    return _session_local

Base = get_base()

def get_db():
    db = get_session_local()()
    try:
        yield db
    finally:
        db.close()

def engine_connection_test():
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except:
        return False