"""
Módulo de logging centralizado para la aplicación.
Proporciona logging a archivo y consola con formato uniforme.
"""

import logging
import os
from datetime import datetime
from logging.handlers import RotatingFileHandler

# Crear directorio de logs si no existe
LOG_DIR = "logs"
os.makedirs(LOG_DIR, exist_ok=True)


def get_logger(name: str) -> logging.Logger:
    """
    Obtiene un logger configurado con handlers para archivo y consola.
    
    Args:
        name: Nombre del logger (típicamente __name__)
    
    Returns:
        logging.Logger: Logger configurado
    
    Ejemplo:
        >>> from app.logger import get_logger
        >>> logger = get_logger(__name__)
        >>> logger.info("Mi mensaje")
    """
    logger = logging.getLogger(name)
    
    # Solo configurar si no tiene handlers (evitar duplicados)
    if not logger.handlers:
        logger.setLevel(logging.DEBUG)
        
        # ========== HANDLER PARA ARCHIVO ==========
        # Usar RotatingFileHandler para rotar archivos por tamaño
        log_file = os.path.join(
            LOG_DIR, 
            f"app_{datetime.now().strftime('%Y%m%d')}.log"
        )
        
        file_handler = RotatingFileHandler(
            log_file,
            maxBytes=10 * 1024 * 1024,  # 10 MB
            backupCount=5  # Guardar 5 archivos anteriores
        )
        file_handler.setLevel(logging.DEBUG)
        
        # ========== HANDLER PARA CONSOLA ==========
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        
        # ========== FORMATO ==========
        # Formato detallado para archivo
        file_formatter = logging.Formatter(
            '%(asctime)s | %(name)s | %(levelname)-8s | %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        
        # Formato simplificado para consola
        console_formatter = logging.Formatter(
            '%(levelname)-8s | %(name)s | %(message)s'
        )
        
        file_handler.setFormatter(file_formatter)
        console_handler.setFormatter(console_formatter)
        
        # Agregar handlers al logger
        logger.addHandler(file_handler)
        logger.addHandler(console_handler)
        
        # Evitar propagación a loggers padres
        logger.propagate = False
    
    return logger


# ========== EJEMPLO DE USO EN LAS VISTAS ==========
"""
# En inventario_view.py:
from app.logger import get_logger

logger = get_logger(__name__)

class InventarioView(ft.Container):
    def _load_categorias(self):
        logger.info("Iniciando carga de categorías")
        try:
            db = next(get_db())
            categorias = db.query(Categoria).all()
            logger.debug(f"Se cargaron {len(categorias)} categorías")
            # ... resto del código
        except ConnectionError as e:
            logger.error(f"Error de conexión a BD: {e}", exc_info=True)
            self._show_error("Error de conexión")
        except Exception as e:
            logger.exception(f"Error inesperado al cargar categorías: {e}")
        finally:
            if db:
                db.close()
"""