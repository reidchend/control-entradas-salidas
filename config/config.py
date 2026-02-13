import os
from typing import Optional
from pydantic_settings import BaseSettings
from dotenv import load_dotenv

# --- CORRECCIÓN PARA ANDROID ---
# Buscamos la ruta absoluta del archivo .env relativo a este archivo config.py
basedir = os.path.abspath(os.path.dirname(__file__))
# Si config.py está en la carpeta /config, el .env está un nivel arriba (..)
env_path = os.path.join(basedir, "..", ".env")

# Si el .env existe en esa ruta, lo cargamos. 
# Si no, load_dotenv() buscará por defecto.
if os.path.exists(env_path):
    load_dotenv(env_path)
else:
    load_dotenv()
# ------------------------------

class Settings(BaseSettings):
    DB_TYPE: str = os.getenv("DB_TYPE", "postgresql")
    DB_HOST: str = os.getenv("DB_HOST", "localhost")
    DB_PORT: str = os.getenv("DB_PORT", "6543")
    DB_NAME: str = os.getenv("DB_NAME", "postgres")
    DB_USER: str = os.getenv("DB_USER", "postgres")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "")
    
    @property
    def DATABASE_URL(self) -> str:
        if self.DB_TYPE.lower() == "sqlite":
            return f"sqlite:///{self.SQLITE_PATH}"
        
        port_str = str(self.DB_PORT).strip()
        final_port = port_str if port_str.isdigit() else "5432"
        
        # Este es el error que viste en la captura:
        if not self.DB_PASSWORD:
            raise ValueError(
                f"DB_PASSWORD no está configurada. "
                f"Buscando en: {env_path}" # Agregamos esto para depurar si falla
            )
        
        return f"postgresql+pg8000://{self.DB_USER}:{self.DB_PASSWORD}@{self.DB_HOST}:{final_port}/{self.DB_NAME}"
    
    FLET_APP_NAME: str = os.getenv("FLET_APP_NAME", "Lycoris_Control")
    FLET_APP_ICON: str = "favicon.png"
    FLET_APP_VERSION: str = os.getenv("FLET_APP_VERSION", "1.0.0")
    
    FLET_WEB_PORT: str = os.getenv("FLET_WEB_PORT", "8502")
    FLET_WEB_HOST: str = os.getenv("FLET_WEB_HOST", "0.0.0.0")
    SECRET_KEY: str = os.getenv("SECRET_KEY", "dev_key")
    DEBUG: str = os.getenv("DEBUG", "False")
    UPLOAD_DIR: str = os.getenv("UPLOAD_DIR", "./uploads")
    MAX_FILE_SIZE: str = os.getenv("MAX_FILE_SIZE", "10485760")
    SQLITE_PATH: str = os.getenv("SQLITE_PATH", "./control_entradas_salidas.db")

    class Config:
        # Pydantic también necesita la ruta completa para estar seguro
        env_file = env_path 
        extra = "allow"

_settings: Optional[Settings] = None

def get_settings() -> Settings:
    global _settings
    if _settings is None:
        try:
            _settings = Settings()
        except ValueError as e:
            # Esto saldrá en tu "Código Detective"
            print(f"❌ Error de configuración: {e}")
            raise
    return _settings