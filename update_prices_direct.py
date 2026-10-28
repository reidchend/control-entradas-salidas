#!/usr/bin/env python3
import json
import os
import time
import urllib.parse
import urllib.request
from datetime import datetime

import psycopg

DB_URL = os.environ.get('DATABASE_URL') or 'postgresql://control_app:Reidchendk.11@localhost:5432/control_entradas?sslmode=disable'

def buscar_ml(query):
    url = f"https://api.mercadolibre.com/sites/MLV/search?q={urllib.parse.quote(query)}&limit=10"
    req = urllib.request.Request(url)
    req.add_header('User-Agent', 'Mozilla/5.0')
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
        return data.get('results', [])
    except Exception as e:
        print(f"Error buscando {query}: {e}")
        return []

def main():
    try:
        conn = psycopg.connect(DB_URL)
        cur = conn.cursor()
        cur.execute("SELECT id, nombre, grupo, modelo FROM activos_tipos WHERE activo = TRUE ORDER BY id")
        tipos = cur.fetchall()
        print(f"Encontrados {len(tipos)} tipos activos")
        
        for tipo_id, nombre, grupo, modelo in tipos:
            q = nombre or ''
            if grupo and grupo not in q:
                q = f"{grupo} {q}"
            if modelo and modelo not in q:
                q = f"{q} {modelo}"
            q = q.strip()
            print(f"Buscando: [{tipo_id}] {q}")
            
            results = buscar_ml(q)
            if not results:
                print(f"  Sin resultados")
                time.sleep(1)
                continue
            
            best_price = None
            best_item = None
            for item in results:
                price = item.get('price')
                if not price:
                    continue
                if best_price is None or price < best_price:
                    best_price = price
                    best_item = item
            
            if best_price:
                print(f"  -> Precio encontrado: {best_price} Bs ({best_item.get('title')[:60]})")
                cur.execute(
                    "UPDATE activos_tipos SET precio_referencia = %s, precio_origen = %s, precio_actualizado_at = %s WHERE id = %s",
                    (float(best_price), 'mercadolibre_ve', datetime.now(), tipo_id)
                )
                conn.commit()
            else:
                print(f"  Sin precio válido")
            time.sleep(2)
        
        cur.close()
        conn.close()
        print("Listo")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()
