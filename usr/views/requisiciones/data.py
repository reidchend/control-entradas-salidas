from datetime import datetime

from usr.database.base import get_db_adaptive
from usr.models import Requisicion, RequisicionDetalle, Producto, Existencia, Movimiento


def eliminar_requisicion(req_id):
    """Elimina una requisición y sus detalles."""
    db = next(get_db_adaptive())
    try:
        req = db.query(Requisicion).filter(Requisicion.id == req_id).first()
        if req:
            num = req.numero
            db.delete(req)
            db.commit()
            
            # Encolar eliminación para el servidor usando el numero (llave de negocio)
            from usr.database.sync_queue import get_sync_queue
            queue = get_sync_queue()
            queue.add_pending('requisiciones', 'delete', {'numero': num})
            
            return True
        return False
    except Exception as e:
        print(f"[REQ] Error eliminando requisición: {e}")
        db.rollback()
        return False
    finally:
        db.close()

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


from sqlalchemy.orm import joinedload

def load_requisiciones():
    db = next(get_db_adaptive())
    try:
        return db.query(Requisicion).options(joinedload(Requisicion.detalles)).order_by(Requisicion.fecha_creacion.desc()).all()
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


from sqlalchemy import text

def marcar_detalle_verificado(detalle_id, estado):
    db = next(get_db_adaptive())
    try:
        detalle = db.query(RequisicionDetalle).filter(RequisicionDetalle.id == detalle_id).first()
        if detalle:
            detalle.verificado = estado
            req_num = db.query(Requisicion.numero).filter(Requisicion.id == detalle.requisicion_id).scalar()
            db.commit()
            
            from usr.database.sync_queue import get_sync_queue
            queue = get_sync_queue()
            queue.add_pending('requisicion_detalles', 'update', {
                'verificado': 1 if estado else 0,
                'requisicion_id': detalle.requisicion_id,
                'numero': req_num,
                'producto_id': detalle.producto_id,
                'ingrediente': detalle.ingrediente,
                'cantidad': detalle.cantidad,
            })
            
            return True
        return False
    finally:
        db.close()

def crear_ajuste_stock(producto_id, almacen, nueva_cantidad, motivo, usuario="Admin", peso_total=None):
    """Crea un movimiento de ajuste para corregir la cantidad inicial."""
    db = next(get_db_adaptive())
    try:
        # 1. Obtener cantidad actual
        exist = db.query(Existencia).filter(
            Existencia.producto_id == producto_id,
            Existencia.almacen == almacen
        ).first()
        
        cant_anterior = exist.cantidad if exist else 0
        diff = nueva_cantidad - cant_anterior
        
        # 2. Crear movimiento de ajuste
        mov_data = {
            'producto_id': producto_id,
            'tipo': 'ajuste',
            'cantidad': diff,
            'cantidad_anterior': cant_anterior,
            'cantidad_nueva': nueva_cantidad,
            'almacen': almacen,
            'observaciones': f"Ajuste auditoría: {motivo}",
            'registrado_por': usuario,
            'fecha_movimiento': datetime.now(),
        }
        if peso_total is not None:
            mov_data['peso_total'] = peso_total
        mov = Movimiento(**mov_data)
        db.add(mov)
        
        # 3. Actualizar Existencia
        if exist:
            exist.cantidad = nueva_cantidad
        else:
            db.add(Existencia(producto_id=producto_id, almacen=almacen, cantidad=nueva_cantidad))
            
        db.commit()
        return True
    except Exception as e:
        print(f"[REQ] Error creando ajuste: {e}")
        db.rollback()
        return False
    finally:
        db.close()

def get_requisicion_audit_data(req_id):
    """Obtiene los datos necesarios para la vista de auditoría."""
    db = next(get_db_adaptive())
    try:
        req = db.query(Requisicion).filter(Requisicion.id == req_id).first()
        if not req:
            return None
            
        detalles = db.query(RequisicionDetalle).filter(RequisicionDetalle.requisicion_id == req_id).all()
        
        audit_items = []
        for det in detalles:
            # Stock actual
            exist_orig = db.query(Existencia).filter(
                Existencia.producto_id == det.producto_id,
                Existencia.almacen == req.origen
            ).first()
            exist_dest = db.query(Existencia).filter(
                Existencia.producto_id == det.producto_id,
                Existencia.almacen == req.destino
            ).first()
            
            s_orig = exist_orig.cantidad if exist_orig else 0
            s_dest = exist_dest.cantidad if exist_dest else 0
            cant_tras = det.cantidad
            
            audit_items.append({
                'detalle_id': det.id,
                'producto_id': det.producto_id,
                'ingrediente': det.ingrediente,
                'verificado': det.verificado,
                'origen': {
                    'inicial': s_orig,
                    'trasladada': cant_tras,
                    'final': s_orig - cant_tras
                },
                'destino': {
                    'inicial': s_dest,
                    'trasladada': cant_tras,
                    'final': s_dest + cant_tras
                }
            })
            
        return {
            'requisicion': req,
            'items': audit_items
        }
    finally:
        db.close()

def totalizar_requisicion(req_id, usuario="Admin"):
    """
    1. Lee stock local desde SQLite.
    2. Crea movimientos de salida (origen) y entrada (destino).
    3. Actualiza existencias localmente.
    4. Cambia estado a 'completada'.
    5. Registra en kardex_validaciones.
    6. Sincroniza cambios a Supabase via sync queue.
    (Todo sobre una sola conexión SQLite para evitar "database is locked".)
    """
    from config.config import get_settings
    device_id = get_settings().DEVICE_IDENTIFIER

    db = next(get_db_adaptive())
    try:
        req = db.query(Requisicion).filter(Requisicion.id == req_id).first()
        if not req:
            raise ValueError("Requisición no encontrada")
        if req.estado == 'completada':
            print(f"[REQ] Requisición {req.numero} ya está completada, ignorando")
            return True

        detalles = db.query(RequisicionDetalle).filter(RequisicionDetalle.requisicion_id == req_id).all()

        for det in detalles:
            # Leer stock actual (misma sesión db)
            exist_orig = db.query(Existencia).filter(
                Existencia.producto_id == det.producto_id,
                Existencia.almacen == req.origen
            ).first()
            exist_dest = db.query(Existencia).filter(
                Existencia.producto_id == det.producto_id,
                Existencia.almacen == req.destino
            ).first()

            cant_orig_actual = exist_orig.cantidad if exist_orig else 0
            cant_dest_actual = exist_dest.cantidad if exist_dest else 0
            cant_orig_nueva = max(0, cant_orig_actual - det.cantidad)
            cant_dest_nueva = cant_dest_actual + det.cantidad
            now_iso = datetime.now().isoformat()

            # Movimiento salida (origen)
            db.execute(
                text("""INSERT INTO movimientos
(producto_id, tipo, cantidad, cantidad_anterior, cantidad_nueva,
 peso_total, registrado_por, observaciones,
 almacen, fecha_movimiento, created_at, device_id, sincronizado)
VALUES (:p, :t, :c, :ca, :cn, :pt, :rp, :obs, :al, :fm, :ca2, :dv, 0)"""),
                {"p": det.producto_id, "t": "tr_salida", "c": det.cantidad,
                 "ca": cant_orig_actual, "cn": cant_orig_nueva,
                 "pt": 0.0, "rp": usuario,
                 "obs": f"Traslado req #{req.numero} → {req.destino}",
                 "al": req.origen, "fm": now_iso, "ca2": now_iso, "dv": device_id}
            )

            # Movimiento entrada (destino)
            db.execute(
                text("""INSERT INTO movimientos
(producto_id, tipo, cantidad, cantidad_anterior, cantidad_nueva,
 peso_total, registrado_por, observaciones,
 almacen, fecha_movimiento, created_at, device_id, sincronizado)
VALUES (:p, :t, :c, :ca, :cn, :pt, :rp, :obs, :al, :fm, :ca2, :dv, 0)"""),
                {"p": det.producto_id, "t": "tr_entrada", "c": det.cantidad,
                 "ca": cant_dest_actual, "cn": cant_dest_nueva,
                 "pt": 0.0, "rp": usuario,
                 "obs": f"Traslado req #{req.numero} ← {req.origen}",
                 "al": req.destino, "fm": now_iso, "ca2": now_iso, "dv": device_id}
            )

            # Actualizar existencias (misma sesión)
            if exist_orig:
                exist_orig.cantidad = cant_orig_nueva
            if exist_dest:
                exist_dest.cantidad = cant_dest_nueva
            else:
                db.add(Existencia(producto_id=det.producto_id, almacen=req.destino, cantidad=det.cantidad))

            # kardex_validaciones
            db.execute(
                text("INSERT INTO kardex_validaciones (producto_id, requisicion_id, fecha, usuario, cantidad_fisica) VALUES (:p, :r, :f, :u, :c)"),
                {"p": det.producto_id, "r": req.id, "f": now_iso, "u": usuario, "c": det.cantidad}
            )

        req.estado = 'completada'
        req.procesada_por = usuario
        req.fecha_procesamiento = datetime.now()

        # Leer existencias finales para sync (antes de commit, ORM aún accesible)
        detalles_data = []
        stocks_sync = []  # (producto_id, almacen_origen, stock_origen, almacen_destino, stock_destino)
        for det in detalles:
            exist_orig = db.query(Existencia).filter(
                Existencia.producto_id == det.producto_id,
                Existencia.almacen == req.origen
            ).first()
            exist_dest = db.query(Existencia).filter(
                Existencia.producto_id == det.producto_id,
                Existencia.almacen == req.destino
            ).first()
            coa = exist_orig.cantidad if exist_orig else 0
            cda = exist_dest.cantidad if exist_dest else 0
            con = max(0, coa - det.cantidad)
            cdn = cda + det.cantidad

            detalles_data.append({
                'producto_id': det.producto_id, 'ingrediente': det.ingrediente,
                'cantidad': det.cantidad, 'unidad': det.unidad, 'es_pesable': False,
            })
            stocks_sync.append((det.producto_id, req.origen, con, req.destino, cdn))

        # Sincronizar existencias a Supabase ANTES de commit.
        # Si Supabase está online y falla, se revierte todo.
        _sync_existencias_supabase_batch(stocks_sync)

        db.commit()

        # Post-commit: encolar sync (best-effort, no revierte)
        try:
            from usr.database.sync_queue import get_sync_queue
            for det in detalles:
                get_sync_queue().add_pending('kardex_validaciones', 'insert', {
                    'producto_id': det.producto_id,
                    'requisicion_id': req.id,
                    'fecha': datetime.now().isoformat(),
                    'usuario': usuario,
                    'cantidad_fisica': det.cantidad,
                })
        except Exception as e:
            print(f"[REQ] Error encolando kardex sync: {e}")

        try:
            _encolar_requisicion_sync(req, detalles_data)
        except Exception as e:
            print(f"[REQ] Error encolando requisicion sync: {e}")

        return True
    except Exception as e:
        print(f"[REQ] Error totalizando: {e}")
        db.rollback()
        raise e
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


def _encolar_requisicion_sync(req, detalles):
    """Encola la requisición (y sus detalles) para subirla a Supabase y así
    poder consultarla desde otros dispositivos, aunque no esté 'completada'."""
    try:
        from usr.database.sync_queue import get_sync_queue
        queue = get_sync_queue()
        detalles_data = []
        for item in detalles:
            cant, uni = _cantidad_unidad_item(item)
            detalles_data.append({
                'producto_id': item.get('producto_id'),
                'ingrediente': _nombre_detalle(item),
                'cantidad': cant,
                'unidad': uni,
                'verificado': item.get('verificado', False),
            })
        req_data = {
            'id': req.id,
            'numero': req.numero,
            'numero_secuencial': req.numero_secuencial,
            'origen': req.origen,
            'destino': req.destino,
            'estado': req.estado,
            'observaciones': req.observaciones,
            'creada_por': req.creada_por,
            'procesada_por': req.procesada_por,
            'fecha_procesamiento': req.fecha_procesamiento.isoformat() if req.fecha_procesamiento else None,
            'fecha_creacion': req.fecha_creacion.isoformat() if req.fecha_creacion else None,
            'actualizada': req.actualizada.isoformat() if req.actualizada else None,
            'detalles': detalles_data,
        }
        queue.add_pending('requisiciones', 'upsert', req_data)
    except Exception as e:
        print(f"[REQ] Error encolando requisición para sync: {e}")


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
            _encolar_requisicion_sync(editando, detalles)
            return editando

        req = Requisicion(
            numero=f"REQ-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            numero_secuencial=0,
            origen=origen,
            destino=destino,
            estado=estado,
            observaciones=observaciones,
            creada_por=user_id,
            fecha_creacion=datetime.now(),
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
        _encolar_requisicion_sync(req, detalles)
        return req
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _sync_existencias_supabase_batch(stocks):
    """Sincroniza existencias a Supabase antes de commit local.
    
    Args:
        stocks: list of (producto_id, almacen_origen, stock_origen, almacen_destino, stock_destino)
    
    Si está online y falla, levanta excepción para que el caller haga rollback.
    Si está offline, retorna sin error (sync async lo recupera).
    """
    from usr.database.base import is_online
    if not is_online():
        return
    from sqlalchemy import create_engine
    from config.config import get_settings
    settings = get_settings()
    url = settings.DATABASE_URL
    connect_args = {'timeout': 15} if 'pg8000' in url else {'connect_timeout': 15}
    engine = create_engine(url, connect_args=connect_args)
    try:
        with engine.connect() as conn:
            for producto_id, almacen_origen, stock_origen, almacen_destino, stock_destino in stocks:
                conn.execute(
                    text("""INSERT INTO existencias (producto_id, almacen, cantidad, unidad)
VALUES (:p, :a, :c, :u)
ON CONFLICT (producto_id, almacen)
DO UPDATE SET cantidad = :c2, unidad = :u2"""),
                    {"p": producto_id, "a": almacen_origen, "c": stock_origen, "u": "unidad",
                     "c2": stock_origen, "u2": "unidad"}
                )
                conn.execute(
                    text("""INSERT INTO existencias (producto_id, almacen, cantidad, unidad)
VALUES (:p, :a, :c, :u)
ON CONFLICT (producto_id, almacen)
DO UPDATE SET cantidad = :c2, unidad = :u2"""),
                    {"p": producto_id, "a": almacen_destino, "c": stock_destino, "u": "unidad",
                     "c2": stock_destino, "u2": "unidad"}
                )
            conn.commit()
    except Exception as e:
        raise RuntimeError(f"Sync existencias a Supabase falló (transacción local revertida): {e}") from e
    finally:
        engine.dispose()
