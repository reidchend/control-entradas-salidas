from datetime import datetime

from usr.database.base import get_db_adaptive
from usr.models import Requisicion, RequisicionDetalle, Producto, Existencia


def get_almacenes():
    db = next(get_db_adaptive())
    try:
        almacenes = [a[0] for a in db.query(Existencia.almacen).distinct().all()]
    finally:
        db.close()
    if "principal" not in almacenes:
        almacenes.append("principal")
    if "restaurante" not in almacenes:
        almacenes.append("restaurante")
    return almacenes


def get_productos_activos(limit=200):
    db = next(get_db_adaptive())
    try:
        return db.query(Producto).filter(Producto.activo == True).order_by(Producto.nombre).limit(limit).all()
    finally:
        db.close()


def load_requisiciones():
    db = next(get_db_adaptive())
    try:
        return db.query(Requisicion).order_by(Requisicion.fecha_creacion.desc()).all()
    finally:
        db.close()


def contar_detalles(req_id):
    db = next(get_db_adaptive())
    try:
        return db.query(RequisicionDetalle).filter(
            RequisicionDetalle.requisicion_id == req_id
        ).count()
    finally:
        db.close()


def get_detalles(req_id):
    db = next(get_db_adaptive())
    try:
        return db.query(RequisicionDetalle).filter(
            RequisicionDetalle.requisicion_id == req_id
        ).all()
    finally:
        db.close()


def buscar_productos(texto, limit=30):
    db = next(get_db_adaptive())
    try:
        query = db.query(Producto).filter(Producto.activo == True)
        if texto:
            query = query.filter(Producto.nombre.ilike(f"%{texto}%"))
        return query.limit(limit).all()
    finally:
        db.close()


def _nombre_detalle(item):
    return item.get('ingrediente') or item.get('nombre') or 'Desconocido'


def _cantidad_unidad_item(item):
    """Devuelve (cantidad, unidad) efectivos del item.
    - Pesables: la cantidad es el peso en kg y la unidad es 'kg'.
    - Por unidades: la cantidad son unidades y la unidad es la del producto.
    """
    if item.get('es_pesable'):
        return (item.get('peso') or 0), 'kg'
    return (item.get('cantidad') or 0), item.get('unidad', 'unidad')


def guardar_requisicion(origen, destino, observaciones, detalles,
                         editando=None, user_id="Admin",
                         estado="pendiente", mover_stock=False):
    """Crea o actualiza una requisición y sus detalles.

    - Si `editando` se pasa, se actualiza esa requisición (se reemplazan sus detalles).
    - Si `mover_stock=True` (flujo de diálogo), transfiere existencias origen->destino
      y el estado queda en 'completada'. Si es False (flujo de vista), solo se registra.
    """
    db = next(get_db_adaptive())
    try:
        if editando:
            editando.origen = origen
            editando.destino = destino
            editando.observaciones = observaciones
            for d in list(editando.detalles):
                db.delete(d)
            db.flush()
            for item in detalles:
                cant, uni = _cantidad_unidad_item(item)
                db.add(RequisicionDetalle(
                    requisicion_id=editando.id,
                    producto_id=item.get('producto_id'),
                    ingrediente=_nombre_detalle(item),
                    cantidad=cant,
                    unidad=uni,
                ))
            db.commit()
            return editando

        req = Requisicion(
            numero=f"REQ-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            numero_secuencial=0,
            origen=origen,
            destino=destino,
            estado=estado,
            observaciones=observaciones,
            creada_por=user_id,
        )
        db.add(req)
        db.flush()

        for item in detalles:
            cant, uni = _cantidad_unidad_item(item)
            db.add(RequisicionDetalle(
                requisicion_id=req.id,
                producto_id=item.get('producto_id'),
                ingrediente=_nombre_detalle(item),
                cantidad=cant,
                unidad=uni,
            ))
            if mover_stock:
                producto_id = item.get('producto_id')
                if producto_id and cant:
                    exist_orig = db.query(Existencia).filter(
                        Existencia.producto_id == producto_id,
                        Existencia.almacen == origen
                    ).first()
                    if exist_orig:
                        exist_orig.cantidad = max(0, (exist_orig.cantidad or 0) - cant)

                    exist_dest = db.query(Existencia).filter(
                        Existencia.producto_id == producto_id,
                        Existencia.almacen == destino
                    ).first()
                    if exist_dest:
                        exist_dest.cantidad = (exist_dest.cantidad or 0) + cant
                    else:
                        db.add(Existencia(
                            producto_id=producto_id,
                            almacen=destino,
                            cantidad=cant
                        ))

        db.commit()
        return req
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
