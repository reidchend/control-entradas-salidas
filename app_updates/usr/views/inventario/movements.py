from datetime import datetime
from usr.database.local_replica import LocalReplica
from usr.database.base import is_online
from usr.notifications import show_success, show_error as show_error_notif
from usr.views.inventario.helpers import get_attr


def registrar_movimiento(page, producto_seleccionado, tipo, cantidad, peso_total=0.0, almacen=None):
    producto_id = get_attr(producto_seleccionado, 'id')
    almacen_seleccionado = almacen or get_attr(producto_seleccionado, 'almacen_predeterminado', 'principal') or 'principal'

    try:
        user_id = str(page.session.get("user_id")) if page else None
        if not user_id:
            user_id = "sistema"
    except Exception:
        user_id = "sistema"

    existencia_actual = LocalReplica.get_existencias_by_producto_almacen(producto_id, almacen_seleccionado)
    cant_anterior = existencia_actual.get('cantidad', 0) if existencia_actual else 0

    es_pesable = get_attr(producto_seleccionado, 'es_pesable', False)

    if es_pesable and peso_total > 0:
        cantidad_a_mover = peso_total
        unidad = 'kg'
    else:
        cantidad_a_mover = cantidad
        unidad = get_attr(producto_seleccionado, 'unidad_medida', 'unidad')

    if tipo == "entrada":
        cant_nueva = cant_anterior + cantidad_a_mover
    else:
        if cant_anterior < cantidad_a_mover:
            show_error_notif("Stock insuficiente")
            return False
        cant_nueva = cant_anterior - cantidad_a_mover

    movimiento_data = {
        "producto_id": producto_id,
        "tipo": tipo,
        "cantidad": cantidad,
        "cantidad_anterior": cant_anterior,
        "cantidad_nueva": cant_nueva,
        "peso_total": peso_total,
        "almacen": almacen_seleccionado,
        "registrado_por": user_id,
        "observaciones": "",
        "fecha_movimiento": datetime.now().isoformat(),
    }

    LocalReplica.save_movimiento(movimiento_data, skip_sync=True)
    LocalReplica.update_existencia(producto_id, almacen_seleccionado, cant_nueva, unidad)

    local_id = movimiento_data.get('id')

    sync_mgr = None
    try:
        from usr.database import get_sync_manager
        sync_mgr = get_sync_manager()
    except Exception:
        pass

    online = is_online() if sync_mgr is None else sync_mgr.check_connection()

    if online:
        try:
            from sqlalchemy import create_engine, text
            from config.config import get_settings
            settings = get_settings()
            remote_engine = create_engine(settings.DATABASE_URL)

            with remote_engine.connect() as conn:
                mov_clean = {k: v for k, v in movimiento_data.items()
                           if k not in ('sincronizado', 'created_at')}
                mov_clean.pop('id', None)

                cols = ", ".join(mov_clean.keys())
                vals = ", ".join([f":{k}" for k in mov_clean.keys()])
                sql = text(f"INSERT INTO movimientos ({cols}) VALUES ({vals})")
                conn.execute(sql, mov_clean)
                conn.commit()

                exist_sql = text("""
                    INSERT INTO existencias (producto_id, almacen, cantidad, unidad)
                    VALUES (:producto_id, :almacen, :cantidad, :unidad)
                    ON CONFLICT (producto_id, almacen)
                    DO UPDATE SET cantidad = :cantidad, unidad = :unidad
                """)
                conn.execute(exist_sql, {
                    'producto_id': producto_id,
                    'almacen': almacen_seleccionado,
                    'cantidad': cant_nueva,
                    'unidad': unidad
                })
                conn.commit()

            remote_engine.dispose()

            if local_id:
                LocalReplica.mark_movimiento_sincronizado(local_id)

            print("[SYNC] Movimiento syncado inmediatamente")
        except Exception as e:
            print(f"[SYNC] Error al syncar: {e}")
            _encolar_sync(movimiento_data)
    else:
        _encolar_sync(movimiento_data)

    show_success(f"{tipo.capitalize()} registrada: {cantidad}")
    return True


def _encolar_sync(movimiento_data):
    try:
        from usr.database.sync_queue import get_sync_queue
        queue = get_sync_queue()
        queue.add_pending('movimientos', 'insert', movimiento_data)
        print(f"[SYNC] Movimiento encolado: {movimiento_data.get('id', 'sin-id')}")
    except Exception as e:
        print(f"[SYNC] Error cola: {e}")
        try:
            from usr.notifications import show_error_with_copy
            show_error_with_copy("Error al encolar movimiento para sync", e)
        except:
            pass


def ajustar_existencia(page, producto_seleccionado, almacen, nueva_cantidad, motivo=""):
    """Ajusta el stock de un producto en un almacén al conteo físico real.

    Registra un movimiento tipo 'ajuste' con la diferencia y actualiza la existencia.
    """
    producto_id = get_attr(producto_seleccionado, 'id')
    almacen_seleccionado = almacen or get_attr(producto_seleccionado, 'almacen_predeterminado', 'principal') or 'principal'

    try:
        user_id = str(page.session.get("user_id")) if page else None
        if not user_id:
            user_id = "sistema"
    except Exception:
        user_id = "sistema"

    existencia_actual = LocalReplica.get_existencias_by_producto_almacen(producto_id, almacen_seleccionado)
    cant_anterior = existencia_actual.get('cantidad', 0) if existencia_actual else 0

    if abs(nueva_cantidad - cant_anterior) < 1e-9:
        show_success("Sin cambios, no se crea movimiento.")
        return True

    diferencia = nueva_cantidad - cant_anterior
    es_pesable = get_attr(producto_seleccionado, 'es_pesable', False)
    unidad = get_attr(producto_seleccionado, 'unidad_medida', 'unidad')

    movimiento_data = {
        "producto_id": producto_id,
        "tipo": "ajuste",
        "cantidad": abs(diferencia),
        "cantidad_anterior": cant_anterior,
        "cantidad_nueva": nueva_cantidad,
        "peso_total": nueva_cantidad if es_pesable else 0.0,
        "almacen": almacen_seleccionado,
        "registrado_por": user_id,
        "observaciones": motivo or "",
        "fecha_movimiento": datetime.now().isoformat(),
    }

    LocalReplica.save_movimiento(movimiento_data, skip_sync=True)
    LocalReplica.update_existencia(producto_id, almacen_seleccionado, nueva_cantidad, unidad)

    local_id = movimiento_data.get('id')

    sync_mgr = None
    try:
        from usr.database import get_sync_manager
        sync_mgr = get_sync_manager()
    except Exception:
        pass

    online = is_online() if sync_mgr is None else sync_mgr.check_connection()

    if online:
        try:
            from sqlalchemy import create_engine, text
            from config.config import get_settings
            settings = get_settings()
            remote_engine = create_engine(settings.DATABASE_URL)

            with remote_engine.connect() as conn:
                mov_clean = {k: v for k, v in movimiento_data.items()
                             if k not in ('sincronizado', 'created_at')}
                mov_clean.pop('id', None)

                cols = ", ".join(mov_clean.keys())
                vals = ", ".join([f":{k}" for k in mov_clean.keys()])
                sql = text(f"INSERT INTO movimientos ({cols}) VALUES ({vals})")
                conn.execute(sql, mov_clean)
                conn.commit()

                exist_sql = text("""
                    INSERT INTO existencias (producto_id, almacen, cantidad, unidad)
                    VALUES (:producto_id, :almacen, :cantidad, :unidad)
                    ON CONFLICT (producto_id, almacen)
                    DO UPDATE SET cantidad = :cantidad, unidad = :unidad
                """)
                conn.execute(exist_sql, {
                    'producto_id': producto_id,
                    'almacen': almacen_seleccionado,
                    'cantidad': nueva_cantidad,
                    'unidad': unidad
                })
                conn.commit()

            remote_engine.dispose()

            if local_id:
                LocalReplica.mark_movimiento_sincronizado(local_id)

            print("[SYNC] Ajuste syncado inmediatamente")
        except Exception as e:
            print(f"[SYNC] Error al syncar ajuste: {e}")
            _encolar_sync(movimiento_data)
    else:
        _encolar_sync(movimiento_data)

    signo = "+" if diferencia > 0 else "-"
    show_success(f"Ajuste registrado: {signo}{abs(diferencia):.2f} {unidad}")
    return True
