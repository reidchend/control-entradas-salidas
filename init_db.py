#!/usr/bin/env python3
"""
Script de REINICIO TOTAL para Supabase/PostgreSQL.
ADVERTENCIA: Este script ELIMINA todas las tablas y datos existentes
para reconstruir la base de datos con la estructura actualizada.
"""

from app.database.base import engine, Base
from app.models import Categoria, Producto, Movimiento, Factura
from sqlalchemy import text, inspect

def reset_database():
    """Elimina y recrea todas las tablas de la base de datos."""
    print("--- INICIANDO REINICIO DE BASE DE DATOS (SUPABASE/POSTGRES) ---")
    
    try:
        # 1. Conectar y eliminar tablas con CASCADE (necesario en Postgres para llaves foráneas)
        with engine.connect() as conn:
            print("→ Eliminando tablas existentes...")
            # Obtenemos los nombres de las tablas actuales
            inspector = inspect(engine)
            table_names = inspector.get_table_names()
            
            if table_names:
                # En Postgres es mejor usar DROP TABLE ... CASCADE para no tener errores de FK
                for table in table_names:
                    print(f"  × Eliminando tabla: {table}")
                    conn.execute(text(f'DROP TABLE IF EXISTS "{table}" CASCADE'))
                conn.commit()
                print("✓ Todas las tablas anteriores han sido eliminadas.")
            else:
                print("○ No se encontraron tablas previas para eliminar.")

        # 2. Crear las tablas nuevamente basadas en los modelos actuales
        print("\n→ Reconstruyendo tablas desde los modelos de la App...")
        Base.metadata.create_all(bind=engine)
        print("✓ Estructura de tablas creada exitosamente.")

        # 3. Validación de columnas críticas
        inspector = inspect(engine)
        print("\n→ Validando columnas para pesaje y stock:")
        
        columnas_producto = [c['name'] for c in inspector.get_columns('productos')]
        if 'es_pesable' in columnas_producto:
            print("  ✓ Columna 'es_pesable' en 'productos' detectada.")
        else:
            print("  ✗ ERROR: La columna 'es_pesable' no se creó en 'productos'.")

        columnas_movimiento = [c['name'] for c in inspector.get_columns('movimientos')]
        if 'peso_total' in columnas_movimiento:
            print("  ✓ Columna 'peso_total' en 'movimientos' detectada.")
        else:
            print("  ✗ ERROR: La columna 'peso_total' no se creó en 'movimientos'.")

        print("\n" + "="*50)
        print("¡ÉXITO! La base de datos en Supabase ha sido reiniciada.")
        print("Ahora puedes iniciar la aplicación con una base limpia.")
        print("="*50)
        return True

    except Exception as e:
        print(f"\n✗ ERROR CRÍTICO DURANTE EL REINICIO: {e}")
        return False

if __name__ == "__main__":
    # Pregunta de seguridad básica (puedes comentarla si lo corres en entorno automatizado)
    confirmar = input("¿ESTÁS SEGURO? Se borrarán TODOS los datos en Supabase (s/n): ")
    if confirmar.lower() == 's':
        success = reset_database()
        exit(0 if success else 1)
    else:
        print("Operación cancelada.")
        exit(0)