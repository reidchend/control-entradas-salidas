import os
from typing import Optional
from pathlib import Path
from pydantic_settings import BaseSettings
from dotenv import load_dotenv

# --- NUEVA LÓGICA DE BÚSQUEDA PARA ANDROID ---
# Definimos las rutas donde el APK podría haber guardado el .env
basedir = Path(__file__).parent
posibles_rutas = [
    basedir.parent / ".env",   # Raíz del proyecto (../.env)
    basedir / ".env",          # Dentro de la carpeta config/
    Path.cwd() / ".env",       # Directorio de trabajo actual
]

env_path = None
for ruta in posibles_rutas:
    if ruta.exists():
        env_path = str(ruta)
        load_dotenv(env_path)
        break
# ---------------------------------------------

class Settings(BaseSettings):
    # --- TU CONFIGURACIÓN ORIGINAL (Mantenida intacta) ---
    DB_TYPE: str = os.getenv("DB_TYPE", "postgresql")
    DB_HOST: str = os.getenv("DB_HOST", "localhost")
    DB_PORT: str = os.getenv("DB_PORT", "6543")
    DB_NAME: str = os.getenv("DB_NAME", "postgres")
    DB_USER: str = os.getenv("DB_USER", "postgres")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "")
    
    @property
    def DATABASE_URL(self) -> str:
        """Construye la URL de conexión a la base de datos de forma segura."""
        if self.DB_TYPE.lower() == "sqlite":
            return f"sqlite:///{self.SQLITE_PATH}"
        
        port_str = str(self.DB_PORT).strip()
        final_port = port_str if port_str.isdigit() else "5432"
        
        # Validación mejorada con diagnóstico de rutas
        if not self.DB_PASSWORD:
            rutas_vistas = "\n".join([str(r) for r in posibles_rutas])
            raise ValueError(
                f"DB_PASSWORD no está configurada.\n"
                f"Se buscó el archivo .env en:\n{rutas_vistas}\n"
                f"Archivo cargado actualmente: {env_path}"
            )
        
        return f"postgresql+pg8000://{self.DB_USER}:{self.DB_PASSWORD}@{self.DB_HOST}:{final_port}/{self.DB_NAME}"
    
    # --- EL RESTO DE TUS VARIABLES ORIGINALES ---
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
        # Usamos la ruta encontrada dinámicamente
        env_file = env_path if env_path else ".env"
        extra = "allow"

# --- TU PATRÓN SINGLETON ORIGINAL ---
_settings: Optional[Settings] = None

def get_settings() -> Settings:
    global _settings
    if _settings is None:
        try:
            _settings = Settings()
        except ValueError as e:
            # Esto permitirá que tu código "Detective" atrape el error
            print(f"❌ Error de configuración: {e}")
            raise
    return _settings