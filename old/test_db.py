# Crear archivo test_db.py en la raíz
from app.database.base import get_db
from app.models import Categoria
from app.logger import get_logger

logger = get_logger(__name__)

def test_db_connection():
    logger.info("Probando conexión a BD...")
    try:
        db = next(get_db())
        categorias = db.query(Categoria).all()
        logger.info(f"✓ Conexión exitosa. Se encontraron {len(categorias)} categorías")
        db.close()
        return True
    except Exception as e:
        logger.error(f"✗ Error de conexión: {e}")
        return False

if __name__ == "__main__":
    test_db_connection()