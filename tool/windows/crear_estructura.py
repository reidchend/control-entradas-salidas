"""Crea la estructura de la base local aplicando los archivos de esquema.

Se ejecuta desde `crear_estructura.bat`, que aporta las credenciales del
superusuario por variables de entorno.

El orden importa: `schema_activos.sql` reutiliza la función
`set_pos_updated_at()` que define `schema.sql`, así que `schema.sql` debe
aplicarse primero.
"""

import os
import sys

import psycopg

# Orden validado contra un PostgreSQL 18 limpio (2026-09-29): la base
# resultante cubre las 37 tablas que la app consulta.
#
# `20260922000000_activos_tipos.sql` se excluye a propósito: no es un
# bootstrap sino la transformación de la antigua tabla `activos` plana
# (con `cantidad`) a unidades individuales. `schema_activos.sql` ya deja
# esa estructura final, así que aplicarla aquí solo fallaría en backfills
# que dependen de columnas que ya no existen.
ARCHIVOS = [
    ("supabase/schema.sql", "esquema base"),
    ("supabase/schema_activos.sql", "categorías, tipos y unidades de activos"),
    ("supabase/migrations/20250101000000_add_dispositivo_usuario.sql",
     "tabla dispositivo_usuario (identificación del equipo)"),
    ("supabase/migrations/20250102000000_add_device_id.sql",
     "columna device_id en dispositivo_usuario"),
    ("supabase/migrations/20250103000000_add_pos_temporales_rls.sql",
     "política RLS de pos_temporales (inertes sin rol supabase)"),
    ("supabase/migrations/20260826000000_add_pos_sesiones_whatsapp_queue.sql",
     "turnos de caja del POS y cola de WhatsApp"),
    ("supabase/migrations/20260827000000_add_pos_cierres.sql",
     "cierres de caja históricos"),
    ("supabase/migrations/20260901000000_add_stock_fecha_checkpoint.sql",
     "columnas extra en stock_checkpoint y movimientos_archivo"),
    ("supabase/migrations/20260901120000_add_almacenes.sql",
     "catálogo de almacenes"),
]


def conexion() -> psycopg.Connection:
    """Abre conexión como superusuario usando las variables de entorno."""
    password = os.environ.get("PGPASSWORD", "")
    dsn = (
        f"host={os.environ.get('PGHOST', 'localhost')} "
        f"port={os.environ.get('PGPORT', '5432')} "
        f"dbname={os.environ.get('PGDATABASE', 'control_entradas')} "
        f"user={os.environ.get('PGUSER', 'postgres')}"
    )
    if password:
        dsn += f" password={password}"
    return psycopg.connect(dsn, autocommit=True)


def main() -> int:
    raiz = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    try:
        conn = conexion()
    except psycopg.Error as e:
        print(f"ERROR: no se pudo conectar: {e}", file=sys.stderr)
        return 1

    with conn:
        for relativo, descripcion in ARCHIVOS:
            ruta = os.path.join(raiz, relativo)
            if not os.path.exists(ruta):
                print(f"ERROR: no existe {relativo}", file=sys.stderr)
                return 1
            print(f"  aplicando {relativo} ({descripcion})...")
            try:
                with open(ruta, encoding="utf-8") as f:
                    conn.execute(f.read())
            except psycopg.Error as e:
                print(f"ERROR: fallo {relativo}: {e}", file=sys.stderr)
                return 1

        cur = conn.execute(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'public' ORDER BY table_name"
        )
        tablas = [r[0] for r in cur.fetchall()]

    print(f"Estructura creada OK. {len(tablas)} tablas en public.")
    esperadas = (
        "activos",
        "activos_tipos",
        "activos_categorias",
        "productos",
        "pos_sesiones",
        "whatsapp_queue",
        "pos_cierres",
        "almacenes",
    )
    faltantes = [t for t in esperadas if t not in tablas]
    if faltantes:
        print(f"AVISO: faltan tablas esperadas: {', '.join(faltantes)}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
