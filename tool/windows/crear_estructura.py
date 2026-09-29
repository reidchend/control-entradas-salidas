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

ARCHIVOS = [
    ("supabase/schema.sql", "esquema base"),
    ("supabase/schema_activos.sql", "categorías, tipos y unidades de activos"),
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
    esperadas = ("activos", "activos_tipos", "activos_categorias", "productos")
    faltantes = [t for t in esperadas if t not in tablas]
    if faltantes:
        print(f"AVISO: faltan tablas esperadas: {', '.join(faltantes)}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
