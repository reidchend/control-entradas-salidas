#!/usr/bin/env python3
"""Script para visualizar la tabla productos de SQLite."""

import sqlite3

conn = sqlite3.connect('lycoris_local.db')
conn.row_factory = sqlite3.Row
cur = conn.cursor()

# obtener schema
print("=== ESQUEMA DE LA TABLA PRODUCTOS ===")
cur.execute("PRAGMA table_info(productos)")
for row in cur.fetchall():
    print(f"  {row['name']}: {row['type']}")

print("\n=== TODOS LOS PRODUCTOS ===")
cur.execute("SELECT * FROM productos ORDER BY categoria_id, nombre")
rows = cur.fetchall()

print(f"Total: {len(rows)} productos\n")

for row in rows:
    print(f"ID: {row['id']}")
    print(f"  Nombre: {row['nombre']}")
    print(f"  Código: {row['codigo']}")
    print(f"  Categoría ID: {row['categoria_id']}")
    print(f"  Activo: {row['activo']}")
    print(f"  Es pesable: {row['es_pesable']}")
    print(f"  Requiere foto peso: {row['requiere_foto_peso']}")
    print(f"  Peso unitario: {row['peso_unitario']}")
    print(f"  Unidad medida: {row['unidad_medida']}")
    print(f"  Stock actual: {row['stock_actual']}")
    print(f"  Stock mínimo: {row['stock_minimo']}")
    print(f"  Almacén: {row['almacen_predeterminado']}")
    print(f"  Created at: {row['created_at']}")
    print(f"  Updated at: {row['updated_at']}")
    print("-" * 40)

print("\n=== PRODUCTOS POR CATEGORÍA ===")
cur.execute("""
    SELECT categoria_id, COUNT(*) as total 
    FROM productos 
    WHERE activo = 1 
    GROUP BY categoria_id 
    ORDER BY categoria_id
""")
for row in cur.fetchall():
    print(f"  Categoría {row['categoria_id']}: {row['total']} productos")

conn.close()