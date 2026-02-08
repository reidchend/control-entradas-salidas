#!/usr/bin/env python3
"""
Script para inicializar la base de datos y crear todas las tablas necesarias.
Ejecutar con: python init_db.py
"""

from app.database.base import engine, Base
from app.models import Categoria, Producto, Movimiento, Factura

def init_db():
    """Crea todas las tablas en la base de datos"""
    print("Creando tablas en la base de datos...")
    
    try:
        # Crear todas las tablas
        Base.metadata.create_all(bind=engine)
        print("✓ Tablas creadas exitosamente")
        
        # Verificar que se crearon
        from app.database.base import SessionLocal
        db = SessionLocal()
        
        # Intentar una consulta simple
        categorias = db.query(Categoria).all()
        print(f"✓ Tabla 'categorias' accesible ({len(categorias)} registros)")
        
        productos = db.query(Producto).all()
        print(f"✓ Tabla 'productos' accesible ({len(productos)} registros)")
        
        movimientos = db.query(Movimiento).all()
        print(f"✓ Tabla 'movimientos' accesible ({len(movimientos)} registros)")
        
        facturas = db.query(Factura).all()
        print(f"✓ Tabla 'facturas' accesible ({len(facturas)} registros)")
        
        db.close()
        
        print("\n✓ Base de datos lista para usar")
        return True
        
    except Exception as e:
        print(f"✗ Error al crear tablas: {e}")
        return False

if __name__ == "__main__":
    success = init_db()
    exit(0 if success else 1)