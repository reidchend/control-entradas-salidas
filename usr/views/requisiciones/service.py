from datetime import datetime
from usr.database.base import get_db_adaptive
from usr.models import Requisicion, RequisicionDetalle, Producto, Existencia


class RequisicionService:

    @staticmethod
    def get_almacenes(db):
        almacenes_result = db.query(Existencia.almacen).distinct().all()
        almacenes = [a[0] for a in almacenes_result]
        if "principal" not in almacenes:
            almacenes.append("principal")
        if "restaurante" not in almacenes:
            almacenes.append("restaurante")
        return almacenes

    @staticmethod
    def get_productos(db, texto=""):
        query = db.query(Producto).filter(Producto.activo == True)
        if texto:
            query = query.filter(Producto.nombre.ilike(f"%{texto}%"))
        return query.order_by(Producto.nombre).limit(30).all()

    @staticmethod
    def get_existencia(db, producto_id, almacen):
        exist = db.query(Existencia).filter(
            Existencia.producto_id == producto_id,
            Existencia.almacen == almacen
        ).first()
        return exist.cantidad if exist else 0

    @staticmethod
    def get_all_requisiciones(db):
        return db.query(Requisicion).order_by(Requisicion.fecha_creacion.desc()).all()

    @staticmethod
    def get_detalles(db, requisicion_id):
        return db.query(RequisicionDetalle).filter(
            RequisicionDetalle.requisicion_id == requisicion_id
        ).all()

    @staticmethod
    def count_detalles(db, requisicion_id):
        return db.query(RequisicionDetalle).filter(
            RequisicionDetalle.requisicion_id == requisicion_id
        ).count()

    @staticmethod
    def create_requisicion(db, origen, destino, observaciones, productos, user_id="Admin"):
        req = Requisicion(
            numero=f"REQ-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            numero_secuencial=0,
            origen=origen,
            destino=destino,
            estado="pendiente",
            observaciones=observaciones,
            creada_por=user_id,
        )
        db.add(req)
        db.flush()

        for item in productos:
            detalle = RequisicionDetalle(
                requisicion_id=req.id,
                producto_id=item['producto_id'],
                ingrediente=item['nombre'],
                cantidad=item['cantidad'],
                unidad=item['unidad'],
            )
            db.add(detalle)

        db.commit()
        return req

    @staticmethod
    def update_requisicion(db, req, origen, destino, observaciones, productos):
        req.origen = origen
        req.destino = destino
        req.observaciones = observaciones

        for d in req.detalles:
            db.delete(d)
        db.flush()

        for item in productos:
            detalle = RequisicionDetalle(
                requisicion_id=req.id,
                producto_id=item['producto_id'],
                ingrediente=item['nombre'],
                cantidad=item['cantidad'],
                unidad=item['unidad'],
            )
            db.add(detalle)

        db.commit()
