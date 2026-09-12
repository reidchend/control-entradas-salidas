#!/usr/bin/env python3
"""Servidor de desarrollo con logs en la terminal.

Sirve el build de Flutter web elegido y recibe los print() de Flutter web
(LogBridge) imprimiéndolos en la consola, igual que en un script de Python.

Además expone un proxy SQL (/proxy-sql) que permite a la app web (Flutter)
ejecutar consultas parametrizadas contra PostgreSQL sin conexiones TCP directas
(el driver package:postgres usa sockets `dart:io`, que no existen en web).

Uso:
    tool/venv/bin/python tool/server.py [puerto] [web_dir_rel]

web_dir_rel por defecto "build/web" (app de inventario). Para el POS:
    tool/venv/bin/python tool/server.py 8501 build/pos

Requiere psycopg (se instala en el venv con:
    python3 -m venv tool/venv && tool/venv/bin/pip install "psycopg[binary]")
La DATABASE_URL se toma de la variable de entorno o de .env.local.
"""
import base64
import datetime as _dt
import http.server
import json
import os
import re
import ssl
import sys
import threading
import time
import urllib.request
import uuid
from datetime import datetime
from decimal import Decimal

try:
    import psycopg
except ImportError:  # pragma: no cover
    psycopg = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB_REL = sys.argv[2] if len(sys.argv) > 2 else os.path.join("build", "web")
WEB_DIR = os.path.join(ROOT, WEB_REL)
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8123

BCV_SITE_URL = "https://www.bcv.org.ve/"
BCV_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)


def fetch_bcv_html(timeout=15):
    """Descarga el HTML del sitio oficial del BCV (misma petición que el scrape
    del POS). Reintenta sin verificar TLS si no hay certificados CA locales."""
    req = urllib.request.Request(
        BCV_SITE_URL,
        headers={
            "User-Agent": BCV_USER_AGENT,
            "Accept": "*/*",
            "Cache-Control": "no-cache",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            return res.read().decode("utf-8", "replace")
    except Exception:
        ctx = ssl._create_unverified_context()
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as res:
            return res.read().decode("utf-8", "replace")


# Caché del sitio oficial: el BCV a veces responde lento o corta conexiones,
# así que se guarda el último HTML exitoso. Si el refresco falla se devuelve
# el dato viejo (stale) en vez de fallar el request y dejar la UI colgada.
_BCV_CACHE = {"ts": 0.0, "html": None}
_BCV_CACHE_TTL = 30 * 60  # 30 minutos


def get_bcv_html():
    now = time.time()
    if _BCV_CACHE["html"] is not None and now - _BCV_CACHE["ts"] < _BCV_CACHE_TTL:
        return _BCV_CACHE["html"]
    try:
        html = fetch_bcv_html()
        _BCV_CACHE["ts"] = now
        _BCV_CACHE["html"] = html
        return html
    except Exception:
        # BCV caído/lento: sirve la última copia si existe.
        if _BCV_CACHE["html"] is not None:
            return _BCV_CACHE["html"]
        raise


def db_url():
    """URL de conexión a PostgreSQL: env (preferible UNPOOLED para el proxy)
    o .env.local en la raíz del proyecto."""
    for key in ("DATABASE_URL_UNPOOLED", "DATABASE_URL"):
        value = os.environ.get(key)
        if value:
            return value
    env_path = os.path.join(ROOT, ".env.local")
    if os.path.exists(env_path):
        values = {}
        with open(env_path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                values[key.strip()] = value.strip().strip("'").strip('"')
        for key in ("DATABASE_URL_UNPOOLED", "DATABASE_URL"):
            if values.get(key):
                return values[key]
    return None


_PLACEHOLDER_RE = re.compile(r"(\$\d+)")


def convert_placeholders(sql):
    """Convierte los placeholders `$1..$N` del driver Dart a `%s` de psycopg,
    escapando `%` literales en el resto del query."""
    parts = _PLACEHOLDER_RE.split(sql)
    out = []
    for part in parts:
        if part.startswith("$") and part[1:].isdigit():
            out.append("%s")
        else:
            out.append(part.replace("%", "%%"))
    return "".join(out)


def json_value(value):
    """Convierte valores de psycopg a formas serializables como JSON (y
    compatibles con lo que esperan los repos Dart: números, ISO strings)."""
    if value is None or isinstance(value, (bool, int, str)):
        return value
    if isinstance(value, float):
        return value
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, _dt.date)):
        return value.isoformat()
    if isinstance(value, (bytes, bytearray)):
        return _base64.b64encode(value).decode()
    if isinstance(value, (list, tuple)):
        return [json_value(v) for v in value]
    if isinstance(value, dict):
        return {str(k): json_value(v) for k, v in value.items()}
    return str(value)


# Transacciones server-side: el driver web (HttpSqlSession) llama begin,
# ejecuta statements con el txid y termina con commit/rollback.
_TXN_TIMEOUT = 120
_TXN_LAST_CLEANUP = {"ts": 0.0}
_TXNS = {}


# Locks: una conexión psycopg no es thread-safe, así que cada transacción usa
# el suyo; las operaciones autocommit usan una conexión nueva por request.
def _connect_db():
    url = db_url()
    if not url:
        raise RuntimeError("DATABASE_URL no configurada (env o .env.local)")
    # prepare_threshold=None evita prepared statements server-side, que el
    # pooler (PgBouncer) no soporta en modo transaccional.
    return psycopg.connect(url, prepare_threshold=None)


def _cleanup_txns():
    now = time.time()
    if now - _TXN_LAST_CLEANUP["ts"] < 30:
        return
    _TXN_LAST_CLEANUP["ts"] = now
    for txid in list(_TXNS.keys()):
        entry = _TXNS.get(txid)
        if entry and now - entry["ts"] > _TXN_TIMEOUT:
            try:
                entry["conn"].close()
            except Exception:
                pass
            try:
                del _TXNS[txid]
            except Exception:
                pass


def _begin_tx():
    _cleanup_txns()
    conn = _connect_db()
    txid = uuid.uuid4().hex
    _TXNS[txid] = {"conn": conn, "ts": time.time(), "lock": threading.Lock()}
    return txid


def _txn_entry(txid):
    entry = _TXNS.get(txid)
    if not entry:
        raise RuntimeError(f"Transacción {txid!r} no encontrada (expirada?)")
    entry["ts"] = time.time()
    return entry


def _exec_sql(conn, sql, params):
    translated = convert_placeholders(sql)
    with conn.cursor() as cur:
        cur.execute(translated, params or [])
        if cur.description:
            columns = [c.name for c in cur.description]
            rows = [
                {name: json_value(value) for name, value in zip(columns, row)}
                for row in cur.fetchall()
            ]
            affected = cur.rowcount if cur.rowcount is not None else len(rows)
        else:
            rows = []
            affected = cur.rowcount if cur.rowcount is not None else 0
    return rows, affected


def _exec_autocommit(sql, params):
    conn = _connect_db()
    try:
        rows, affected = _exec_sql(conn, sql, params)
        conn.commit()
        return rows, affected
    except Exception:
        conn.rollback()
        raise
    finally:
        try:
            conn.close()
        except Exception:
            pass


def _end_tx(txid, commit):
    entry = _txn_entry(txid)
    try:
        del _TXNS[txid]
    except Exception:
        pass
    with entry["lock"]:
        if commit:
            entry["conn"].commit()
        else:
            entry["conn"].rollback()
        try:
            entry["conn"].close()
        except Exception:
            pass


class WebServer(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def end_headers(self):
        # Evita que el navegador cachee el bundle (SW del dev loop stale).
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _send_json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        # Proxy del sitio oficial del BCV: sortea el CORS que bloquea el fetch
        # desde Flutter web (el navegador no puede pedir www.bcv.org.ve).
        if self.path.split("?")[0] == "/proxy-bcv":
            try:
                html = get_bcv_html()
            except Exception as e:  # noqa: BLE001
                self._send_json(502, {"error": str(e)})
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(html.encode("utf-8"))
            return
        super().do_GET()

    def _handle_proxy_sql(self, body):
        try:
            req = json.loads(body) or {}
        except json.JSONDecodeError as e:
            self._send_json(400, {"error": f"JSON inválido: {e}"})
            return

        if psycopg is None:
            self._send_json(503, {"error": "psycopg no instalado (usa tool/venv)"})
            return

        action = req.get("action", "execute")
        try:
            if action == "begin":
                self._send_json(200, {"txid": _begin_tx()})
                return

            if action in ("commit", "rollback"):
                txid = req.get("txid")
                if not txid:
                    self._send_json(400, {"error": "falta txid"})
                    return
                _end_tx(txid, commit=action == "commit")
                self._send_json(200, {"ok": True})
                return

            # execute / open-sql
            sql = req.get("sql")
            if not isinstance(sql, str) or not sql.strip():
                self._send_json(400, {"error": "falta sql"})
                return
            params = req.get("params") or []
            if not isinstance(params, list):
                self._send_json(400, {"error": "params debe ser una lista"})
                return

            txid = req.get("txid")
            if txid:
                entry = _txn_entry(txid)
                with entry["lock"]:
                    rows, affected = _exec_sql(entry["conn"], sql, params)
            else:
                rows, affected = _exec_autocommit(sql, params)
            self._send_json(200, {"rows": rows, "affectedRows": affected})
        except Exception as e:  # noqa: BLE001
            self._send_json(500, {"error": str(e)})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", "replace")

        if self.path == "/proxy-sql":
            self._handle_proxy_sql(body)
            return

        if self.path != "/log":
            self.send_response(404)
            self.end_headers()
            return

        for line in body.splitlines():
            ts = datetime.now().strftime("%H:%M:%S")
            print(f"[{ts}] {line}", flush=True)

        self.send_response(204)
        self.end_headers()

    def log_message(self, fmt, *args):
        # Suprime los logs HTTP de cada request para no ensuciar la consola.
        pass


if __name__ == "__main__":
    os.makedirs(WEB_DIR, exist_ok=True)
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), WebServer)
    print(f"Serving app at http://0.0.0.0:{PORT} (Ctrl+C to stop)")
    print("Logs de la app aparecen abajo.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nDeteniendo servidor.")