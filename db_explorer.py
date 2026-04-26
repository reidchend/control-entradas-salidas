from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
import sqlite3
import math
from usr.database.conn import get_db_path

app = FastAPI()
DB_PATH = get_db_path()

# Estilos mejorados con soporte para paginación
STYLE = """
<style>
    body { font-family: 'Segoe UI', sans-serif; background: #0f111a; color: #ffffff; margin: 0; padding: 20px; }
    .container { max-width: 100%; margin: auto; padding: 0 20px; }
    h1 { color: #448aff; margin-bottom: 5px; }
    .db-path { color: #666; font-size: 12px; margin-bottom: 20px; }
    
    .nav-tables { display: flex; gap: 8px; overflow-x: auto; padding: 10px 0; margin-bottom: 20px; border-bottom: 1px solid #2d2e3c; }
    .nav-tables a { background: #1a1c25; color: #aaa; text-decoration: none; padding: 8px 16px; border-radius: 4px; font-size: 13px; white-space: nowrap; transition: 0.2s; }
    .nav-tables a:hover, .nav-tables a.active { background: #448aff; color: white; }
    
    .pagination { display: flex; align-items: center; justify-content: center; gap: 20px; margin: 20px 0; background: #1a1c25; padding: 15px; border-radius: 8px; }
    .btn-pag { background: #333; color: white; padding: 8px 20px; text-decoration: none; border-radius: 5px; font-weight: bold; }
    .btn-pag:hover { background: #555; }
    .btn-pag.disabled { background: #222; color: #444; pointer-events: none; }
    
    table { width: 100%; border-collapse: collapse; background: #1a1c25; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.3); }
    th { background: #252836; color: #ff9800; text-align: left; padding: 15px; font-size: 12px; position: sticky; top: 0; }
    td { padding: 12px 15px; border-bottom: 1px solid #2d2e3c; font-size: 13px; color: #ced4da; }
    tr:hover { background: #252836; }
    .badge { background: #448aff; padding: 2px 8px; border-radius: 10px; font-size: 11px; }
</style>
"""

@app.get("/", response_class=HTMLResponse)
async def get_explorer(table: str = None, page: int = 1, limit: int = 50):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # 1. Obtener lista de tablas
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
    tables = [row[0] for row in cursor.fetchall()]
    
    nav_html = "".join([f'<a href="/?table={t}&limit={limit}" class="{"active" if t==table else "" }">{t}</a>' for t in tables])
    
    content_html = ""
    pagination_html = ""

    if table:
        offset = (page - 1) * limit
        
        try:
            # 2. Contar total de registros para saber cuántas páginas hay
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            total_rows = cursor.fetchone()[0]
            total_pages = math.ceil(total_rows / limit)

            # 3. Consulta con LIMIT y OFFSET (Paginación real)
            if table == "movimientos":
                query = f"""
                    SELECT m.id, p.nombre, m.tipo, m.cantidad, m.fecha_movimiento 
                    FROM movimientos m 
                    LEFT JOIN productos p ON m.producto_id = p.id 
                    ORDER BY m.id DESC LIMIT ? OFFSET ?
                """
                cursor.execute(query, (limit, offset))
                cols = ["ID", "Producto", "Tipo", "Cantidad", "Fecha"]
            else:
                query = f"SELECT * FROM {table} LIMIT ? OFFSET ?"
                cursor.execute(query, (limit, offset))
                cols = [d[0] for d in cursor.description]
            
            rows = cursor.fetchall()

            # Construir botones de paginación
            prev_class = "disabled" if page <= 1 else ""
            next_class = "disabled" if page >= total_pages else ""
            
            pagination_html = f"""
            <div class="pagination">
                <a href="/?table={table}&page={page-1}&limit={limit}" class="btn-pag {prev_class}">« Anterior</a>
                <span>Página <b>{page}</b> de {total_pages} <small>({total_rows} registros totales)</small></span>
                <a href="/?table={table}&page={page+1}&limit={limit}" class="btn-pag {next_class}">Siguiente »</a>
            </div>
            """

            # Construir tabla HTML
            table_head = "".join([f"<th>{c}</th>" for c in cols])
            table_body = "".join([f"<tr>{''.join([f'<td>{val}</td>' for val in row])}</tr>" for row in rows])
            
            content_html = f"""
                <div style="display:flex; justify-content: space-between; align-items: center;">
                    <h2>Tabla: {table} <span class="badge">{total_rows}</span></h2>
                </div>
                <table><thead>{table_head}</thead><tbody>{table_body}</tbody></table>
            """
        except Exception as e:
            content_html = f"<p style='color:red; background:#300; padding:20px;'>Error al cargar datos: {e}</p>"
    else:
        content_html = "<div style='text-align:center; padding:100px; color:#555;'><h3>Selecciona una tabla para comenzar a explorar</h3></div>"

    conn.close()
    
    return f"""
    <html>
        <head><title>DB Explorer Paginado</title>{STYLE}</head>
        <body>
            <div class="container">
                <h1>Explorador de Datos</h1>
                <div class="db-path">Archivo: {DB_PATH}</div>
                <div class="nav-tables">{nav_html}</div>
                {pagination_html}
                {content_html}
                {pagination_html}
            </div>
        </body>
    </html>
    """

if __name__ == "__main__":
    import uvicorn
    # Cambia el puerto si el 8000 está ocupado
    uvicorn.run(app, host="0.0.0.0", port=8000)