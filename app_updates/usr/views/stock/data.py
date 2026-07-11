from sqlalchemy import func
from sqlalchemy.orm import joinedload
from usr.database.base import get_db_adaptive
from usr.models import Producto, Movimiento, Categoria, Existencia, Factura

def load_categories():
    db = next(get_db_adaptive())
    try:
        return db.query(Categoria).filter(Categoria.activo == True).all()
    finally:
        db.close()

def load_warehouses():
    db = next(get_db_adaptive())
    try:
        return db.query(Existencia.almacen).distinct().all()
    finally:
        db.close()

def load_products(limit=50):
    db = next(get_db_adaptive())
    try:
        return db.query(Producto).options(joinedload(Producto.categoria)).filter(Producto.activo == True).order_by(Producto.nombre).limit(limit).all()
    finally:
        db.close()

def get_existencias_map(producto_ids):
    if not producto_ids:
        return {}
    db = next(get_db_adaptive())
    existencias_map = {}
    try:
        existencias = db.query(Existencia.producto_id, Existencia.almacen, Existencia.cantidad).filter(Existencia.producto_id.in_(producto_ids)).all()
        for e in existencias:
            if e.producto_id not in existencias_map:
                existencias_map[e.producto_id] = {}
            existencias_map[e.producto_id][e.almacen] = e.cantidad
    finally:
        db.close()
    return existencias_map

def filter_products_db(search="", categoria=None, almacen=None, stock_status="all", limit=50):
    db = next(get_db_adaptive())
    try:
        query = db.query(Producto).options(joinedload(Producto.categoria)).filter(Producto.activo == True)
        if categoria and categoria.isdigit():
            query = query.filter(Producto.categoria_id == int(categoria))
        if search:
            query = query.filter((Producto.nombre.ilike(f"%{search}%")) | (Producto.codigo.ilike(f"%{search}%")))
        
        productos = query.order_by(Producto.nombre).limit(limit).all()
        producto_ids = [p.id for p in productos]
        existencias_map = get_existencias_map(producto_ids)
        
        # Filtrar por almacén si aplica (usa el stock real por almacén)
        if almacen:
            productos = [p for p in productos if (existencias_map.get(p.id, {}).get(almacen) or 0) > 0]
        
        # Filtrar por estado de stock usando el stock CALCULADO (suma de existencias),
        # que es exactamente lo que se muestra en la tarjeta.
        if stock_status != "all":
            def _stock_calc(p):
                return sum(existencias_map.get(p.id, {}).values()) or 0
            if stock_status == "low":
                productos = [p for p in productos if 0 < _stock_calc(p) <= (p.stock_minimo or 0)]
            elif stock_status == "out":
                productos = [p for p in productos if _stock_calc(p) <= 0]
        
        return productos, existencias_map
    finally:
        db.close()

def get_producto_historial(producto_id, limit=20):
    db = next(get_db_adaptive())
    try:
        movimientos = db.query(Movimiento).options(joinedload(Movimiento.factura)).filter(Movimiento.producto_id == producto_id).order_by(Movimiento.fecha_movimiento.desc()).limit(limit).all()
        return movimientos
    finally:
        db.close()
