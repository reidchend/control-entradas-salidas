"""
Limpia todos los datos de prueba relacionados con requisiciones:
- requisiciones
- requisicion_detalles  
- kardex_validaciones
- movimientos de tipo tr_salida / tr_entrada

Ejecutar desde PC en desarrollo:  python reset_requisiciones.py
"""

import os, sys

# --- Configurar path de la BD local ---
# Buscar .env para la conexión remota
from pathlib import Path

env_paths = [
    Path("config/.env"),
    Path(".env"),
    Path("../.env"),
]

# Cargar .env para credenciales de Supabase
env_loaded = False
for p in env_paths:
    if p.exists():
        from dotenv import load_dotenv
        load_dotenv(p)
        env_loaded = True
        print(f"  .env cargado desde: {p.resolve()}")
        break

if not env_loaded:
    print("  ! No se encontró .env, la conexión remota fallará")

# --- Ruta de la BD local ---
# Intentar obtener del entorno o usar default
db_path = os.environ.get("LYCORIS_DB_PATH")
if not db_path:
    # Ruta por defecto (desarrollo PC)
    db_path = str(Path("lycoris_local.db"))
    
print(f"\n  BD local: {db_path}")
print(f"  DB_TYPE:  {os.getenv('DB_TYPE', 'postgresql')}")
print(f"  DB_HOST:  {os.getenv('DB_HOST', '(no .env)')}")
print()

# --- 1. Limpiar BD local ---
import sqlite3

def limpiar_local():
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    tablas = [
        ("kardex_validaciones", "DELETE FROM kardex_validaciones"),
        ("requisicion_detalles", "DELETE FROM requisicion_detalles"),
        ("requisiciones", "DELETE FROM requisiciones"),
        ("movimientos (tr_salida/tr_entrada)", 
         "DELETE FROM movimientos WHERE tipo IN ('tr_salida', 'tr_entrada')"),
    ]
    
    for nombre, sql in tablas:
        try:
            cursor.execute(sql)
            print(f"  ✓ {nombre}: {cursor.rowcount} filas eliminadas")
        except Exception as e:
            print(f"  ✗ {nombre}: {e}")
    
    conn.commit()
    conn.close()

limpiar_local()

# --- 2. Limpiar Supabase ---
def limpiar_remoto():
    db_type = os.getenv("DB_TYPE", "sqlite")
    if db_type.lower() == "sqlite":
        print("  - DB_TYPE=sqlite, saltando limpieza remota")
        return
    
    from sqlalchemy import create_engine, text
    
    db_user = os.getenv("DB_USER")
    db_pass = os.getenv("DB_PASSWORD")
    db_host = os.getenv("DB_HOST")
    db_port = os.getenv("DB_PORT", "5432")
    db_name = os.getenv("DB_NAME")
    
    if not all([db_user, db_pass, db_host, db_name]):
        print("  ! Faltan credenciales remotas, saltando")
        return
    
    port_str = str(db_port).strip()
    final_port = port_str if port_str.isdigit() else "5432"
    url = f"postgresql+pg8000://{db_user}:{db_pass}@{db_host}:{final_port}/{db_name}"
    connect_args = {'timeout': 15}
    
    try:
        engine = create_engine(url, connect_args=connect_args)
        with engine.connect() as conn:
            tablas = [
                ("kardex_validaciones", "DELETE FROM kardex_validaciones"),
                ("requisicion_detalles", "DELETE FROM requisicion_detalles"),
                ("requisiciones", "DELETE FROM requisiciones"),
                ("movimientos (tr_salida/tr_entrada)",
                 "DELETE FROM movimientos WHERE tipo IN ('tr_salida', 'tr_entrada')"),
            ]
            for nombre, sql in tablas:
                try:
                    result = conn.execute(text(sql))
                    conn.commit()
                    print(f"  ✓ [REMOTO] {nombre}: {result.rowcount} filas eliminadas")
                except Exception as e:
                    conn.rollback()
                    print(f"  ✗ [REMOTO] {nombre}: {e}")
        engine.dispose()
    except Exception as e:
        print(f"  ✗ [REMOTO] Error de conexión: {e}")

limpiar_remoto()

print("\n✅ Limpieza completada")
