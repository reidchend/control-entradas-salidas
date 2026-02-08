import os
from typing import Optional
from pydantic_settings import BaseSettings
from dotenv import load_dotenv

load_dotenv()

class Settings(BaseSettings):
    # --- CONFIGURACIÓN DE BASE DE DATOS ---
    # Ahora cargamos desde variables de entorno, NO hardcodeadas
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
        
        # Forzamos que si el puerto es cualquier cosa no numérica, use 5432
        port_str = str(self.DB_PORT).strip()
        final_port = port_str if port_str.isdigit() else "5432"
        
        # Validar que haya contraseña
        if not self.DB_PASSWORD:
            raise ValueError(
                "DB_PASSWORD no está configurada. "
                "Por favor, configura las variables de entorno en .env"
            )
        
        return f"postgresql+pg8000://{self.DB_USER}:{self.DB_PASSWORD}@{self.DB_HOST}:{final_port}/{self.DB_NAME}"
    
    # --- CONFIGURACIÓN DE LA APP ---
    FLET_APP_NAME: str = os.getenv("FLET_APP_NAME", "Lycoris_Control")
    FLET_APP_ICON: str = "favicon.png"
    FLET_APP_VERSION: str = os.getenv("FLET_APP_VERSION", "1.0.0")
    
    # --- OTRAS CONFIGURACIONES ---
    FLET_WEB_PORT: str = os.getenv("FLET_WEB_PORT", "8502")
    FLET_WEB_HOST: str = os.getenv("FLET_WEB_HOST", "0.0.0.0")
    SECRET_KEY: str = os.getenv("SECRET_KEY", "dev_key")
    DEBUG: str = os.getenv("DEBUG", "False")
    UPLOAD_DIR: str = os.getenv("UPLOAD_DIR", "./uploads")
    MAX_FILE_SIZE: str = os.getenv("MAX_FILE_SIZE", "10485760")
    SQLITE_PATH: str = os.getenv("SQLITE_PATH", "./control_entradas_salidas.db")

    class Config:
        env_file = ".env"
        extra = "allow"

_settings: Optional[Settings] = None

def get_settings() -> Settings:
    """
    Obtiene la instancia única de configuración.
    Usa patrón Singleton para asegurar que solo hay una instancia.
    """
    global _settings
    if _settings is None:
        try:
            _settings = Settings()
        except ValueError as e:
            print(f"❌ Error de configuración: {e}")
            print("Por favor, asegúrate de que el archivo .env está configurado correctamente.")
            raise
    return _settings