#!/usr/bin/env python3
import json
import os
import time
import urllib.parse
import urllib.request
from datetime import datetime

PROXY_URL = os.environ.get('PROXY_URL') or 'http://127.0.0.1:7070/proxy-sql'
PROXY_TOKEN = os.environ.get('PROXY_TOKEN') or 'Reidchendk.11'

def proxy_request(action, sql=None, params=None, txid=None):
    body = {'action': action}
    if sql is not None:
        body['sql'] = sql
    if params is not None:
        body['params'] = params
    if txid is not None:
        body['txid'] = txid
    
    req = urllib.request.Request(
        PROXY_URL,
        data=json.dumps(body).encode('utf-8'),
        headers={
            'Content-Type': 'application/json',
            'X-Proxy-Token': PROXY_TOKEN
        },
        method='POST'
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception as e:
        print(f"Proxy error: {e}")
        raise

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
    # Obtener tipos activos
    res = proxy_request('execute', sql="SELECT id, nombre, grupo, modelo FROM activos_tipos WHERE activo = TRUE ORDER BY id")
    tipos = res.get('rows', [])
    print(f"Encontrados {len(tipos)} tipos activos")
    
    for tipo in tipos:
        tipo_id = tipo['id']
        nombre = tipo.get('nombre') or ''
        grupo = tipo.get('grupo') or ''
        modelo = tipo.get('modelo') or ''
        
        # Construir query
        q = nombre
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
            proxy_request('execute', 
                sql="UPDATE activos_tipos SET precio_referencia = %s, precio_origen = %s, precio_actualizado_at = %s WHERE id = %s",
                params=[float(best_price), 'mercadolibre_ve', datetime.now().isoformat(), int(tipo_id)]
            )
        else:
            print(f"  Sin precio válido")
        time.sleep(2)

if __name__ == '__main__':
    main()
