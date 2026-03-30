#!/usr/bin/env python3
"""
Script de migración para agregar soporte de almacenes.
Este script:
1. Agrega columna almacen_predeterminado a productos
2. Migra el stock_actual actual a existencias en almacen 'principal'
3. Agrega columna almacen a movimientos
"""

from config.config import get_settings
from sqlalchemy import create_engine, text, inspect

def migrar():
    settings = get_settings()
    url = f'postgresql+pg8000://{settings.DB_USER}:{settings.DB_PASSWORD}@{settings.DB_HOST}:{settings.DB_PORT}/{settings.DB_NAME}'
    engine = create_engine(url)
    
    print("=" * 60)
    print("MIGRACIÓN DE ALMACENES")
    print("=" * 60)
    
    inspector = inspect(engine)
    
    with engine.connect() as conn:
        # 1. Verificar y agregar columna almacen_predeterminado a productos
        columnas_productos = [c['name'] for c in inspector.get_columns('productos')]
        
        if 'almacen_predeterminado' not in columnas_productos:
            print("→ Agregando columna 'almacen_predeterminado' a productos...")
            conn.execute(text("""
                ALTER TABLE productos 
                ADD COLUMN almacen_predeterminado VARCHAR(50) DEFAULT 'principal'
            """))
            conn.commit()
            print("  ✓ Columna agregada")
        else:
            print("  ✓ Columna 'almacen_predeterminado' ya existe")
        
        # 2. Agregar columna almacen a movimientos si no existe
        columnas_movimientos = [c['name'] for c in inspector.get_columns('movimientos')]
        
        if 'almacen' not in columnas_movimientos:
            print("→ Agregando columna 'almacen' a movimientos...")
            conn.execute(text("""
                ALTER TABLE movimientos 
                ADD COLUMN almacen VARCHAR(50)
            """))
            conn.commit()
            print("  ✓ Columna agregada")
        else:
            print("  ✓ Columna 'almacen' ya existe")
        
        # 3. Migrar stock_actual a existencias (solo si no hay existencias)
        print("→ Migrando stock_actual a existencias...")
        
        result = conn.execute(text("SELECT COUNT(*) FROM existencias")).scalar()
        
        if result == 0:
            # Migrar productos con stock
            productos = conn.execute(text("""
                SELECT id, stock_actual, unidad_medida 
                FROM productos 
                WHERE stock_actual > 0
            """)).fetchall()
            
            for prod in productos:
                conn.execute(text("""
                    INSERT INTO existencias (producto_id, almacen, cantidad, unidad)
                    VALUES (:prod_id, 'principal', :cantidad, :unidad)
                """), {"prod_id": prod[0], "cantidad": prod[1], "unidad": prod[2] or "unidad"})
            
            conn.commit()
            print(f"  ✓ Migrados {len(productos)} productos a existencias")
        else:
            print("  ✓ Ya existen registros en existencias, omitiendo migración")
        
        # 4. Verificar estructura de existencias
        print("→ Verificando estructura de existencias...")
        columnas_existencias = [c['name'] for c in inspector.get_columns('existencias')]
        print(f"  Columnas actuales: {columnas_existencias}")
        
        # Verificar que tenga las columnas necesarias
        requeridas = ['producto_id', 'almacen', 'cantidad', 'unidad']
        for col in requeridas:
            if col in columnas_existencias:
                print(f"  ✓ {col}")
            else:
                print(f"  ✗ FALTA {col} - DEBE AGREGARSE MANUALMENTE")
        
    print("\n" + "=" * 60)
    print("MIGRACIÓN COMPLETADA")
    print("=" * 60)
    print("\nAhora puede ejecutar la aplicación.")

if __name__ == "__main__":
    confirmar = input("¿Ejecutar migración en Supabase? (s/n): ")
    if confirmar.lower() == 's':
        migrar()
    else:
        print("Operación cancelada.")
