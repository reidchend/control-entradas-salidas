#!/usr/bin/env python3
import json
import os
import re
import time
import urllib.parse
from datetime import datetime

import psycopg

try:
    from curl_cffi import requests as cffi_requests
    USE_CFFI = True
    print("Usando curl_cffi")
except Exception as e:
    USE_CFFI = False
    print(f"curl_cffi no disponible: {e}")

DB_URL = os.environ.get('DATABASE_URL') or 'postgresql://control_app:Reidchendk.11@localhost:5432/control_entradas?sslmode=disable'

SCRAPERAPI_KEY = '3f7c3c436e020dafe36093462b414444'


def buscar_ml_scraperapi(query):
    """Consulta MercadoLibre a través de ScraperAPI para evitar bloqueo de IP (Starlink)."""
    if not USE_CFFI or not SCRAPERAPI_KEY:
        return []
    ml_url = f"https://api.mercadolibre.com/sites/MLV/search?q={urllib.parse.quote(query)}&limit=10"
    scraperapi_url = (
        f"http://api.scraperapi.com?api_key={SCRAPERAPI_KEY}"
        f"&url={urllib.parse.quote(ml_url, safe='')}"
    )
    try:
        resp = cffi_requests.get(scraperapi_url, impersonate="chrome124", timeout=40, headers={
            "Accept": "application/json",
        })
        if resp.status_code != 200:
            print(f"  [ScraperAPI] HTTP {resp.status_code}")
            return []
        try:
            data = resp.json()
        except Exception as e:
            print(f"  [ScraperAPI] parse error: {e}")
            return []
        results = data.get('results', []) or []
        return results
    except Exception as e:
        print(f"  [ScraperAPI] error: {e}")
        return []


def buscar_precios_ddg(query):
    """Fallback con DuckDuckGo si ScraperAPI falla."""
    if not USE_CFFI:
        return []
    try:
        url = f"https://html.duckduckgo.com/html/?q={urllib.parse.quote(query + ' venezuela precio')}"
        resp = cffi_requests.get(url, impersonate="chrome124", timeout=30, headers={
            "Accept": "text/html",
            "Accept-Language": "es-VE,es;q=0.9",
        })
        if resp.status_code != 200:
            return []
        html = resp.text
        prices = []
        for m in re.finditer(r'(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})\s*(?:Bs|USD|\$)', html, re.I):
            try:
                s = m.group(1)
                if '.' in s and ',' in s:
                    if s.rfind(',') > s.rfind('.'):
                        s2 = s.replace('.', '').replace(',', '.')
                    else:
                        s2 = s.replace(',', '')
                elif ',' in s and s.count(',') == 1:
                    s2 = s.replace(',', '.')
                elif '.' in s and s.count('.') >= 2:
                    s2 = s.replace('.', '')
                else:
                    s2 = s
                v = float(s2)
                if 100 < v < 10000000:
                    prices.append(v)
            except:
                pass
        for m in re.finditer(r'Bs\.?\s*(\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2})?)', html, re.I):
            try:
                s = m.group(1)
                if '.' in s and ',' in s:
                    if s.rfind(',') > s.rfind('.'):
                        s2 = s.replace('.', '').replace(',', '.')
                    else:
                        s2 = s.replace(',', '')
                elif ',' in s and s.count(',') == 1:
                    s2 = s.replace(',', '.')
                elif '.' in s and s.count('.') >= 2:
                    s2 = s.replace('.', '')
                else:
                    s2 = s
                v = float(s2)
                if 100 < v < 10000000:
                    prices.append(v)
            except:
                pass
        prices = list(set(prices))
        if prices:
            best = min(prices)
            return [{'price': best, 'title': 'duckduckgo-search'}]
        return []
    except Exception:
        return []


def buscar_ml_api_cffi(query):
    """ML directo (fallback, probablemente 403 desde Starlink)."""
    if not USE_CFFI:
        return []
    url = f"https://api.mercadolibre.com/sites/MLV/search?q={urllib.parse.quote(query)}&limit=10"
    try:
        resp = cffi_requests.get(url, impersonate="chrome124", timeout=30, headers={
            "Accept": "application/json",
            "Referer": "https://www.mercadolibre.com.ve/"
        })
        if resp.status_code != 200:
            return []
        try:
            data = resp.json()
        except:
            return []
        return data.get('results', []) or []
    except:
        return []


def buscar_ml(query):
    # 1) MercadoLibre vía ScraperAPI (evita bloqueo de IP)
    res = buscar_ml_scraperapi(query)
    if res:
        return res
    # 2) DuckDuckGo como fallback
    res = buscar_precios_ddg(query)
    if res:
        return res
    # 3) ML directo (último recurso)
    res = buscar_ml_api_cffi(query)
    if res:
        return res
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
            if grupo and grupo.strip().lower() not in (q or '').lower():
                q = f"{grupo} {q}"
            if modelo and modelo.strip().lower() not in (q or '').lower():
                q = f"{q} {modelo}"
            q = q.strip()
            if not q:
                print(f"Buscando: [{tipo_id}] (sin nombre)")
                continue
            print(f"Buscando: [{tipo_id}] {q}")

            results = buscar_ml(q)
            if not results:
                print(f"  Sin resultados")
                time.sleep(2)
                continue

            best_price = None
            best_item = None
            for item in results:
                price = item.get('price')
                if not price:
                    continue
                try:
                    p = float(price)
                except:
                    continue
                if best_price is None or p < best_price:
                    best_price = p
                    best_item = item

            if best_price:
                title = (best_item.get('title') or '')[:60]
                print(f"  -> Precio encontrado: {best_price} Bs ({title})")
                cur.execute(
                    "UPDATE activos_tipos SET precio_referencia = %s, precio_origen = %s, precio_actualizado_at = %s WHERE id = %s",
                    (float(best_price), 'mercadolibre_ve' if best_item.get('title') != 'duckduckgo-search' else 'busqueda_web', datetime.now(), tipo_id)
                )
                conn.commit()
            else:
                print(f"  Sin precio válido")
            time.sleep(1)

        cur.close()
        conn.close()
        print("Listo")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    main()
