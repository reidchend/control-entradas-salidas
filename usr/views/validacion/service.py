from datetime import datetime
from sqlalchemy import text
from usr.database.base import get_db_adaptive, is_online
from usr.models import Proveedor, Factura, Movimiento, FacturaPago


class ValidacionService:
    @staticmethod
    def procesar(data: dict, selected_entradas: set) -> dict:
        from usr.database.base import get_db_adaptive
        from usr.models import Proveedor, Factura, Movimiento, FacturaPago

        db = None
        try:
            db = next(get_db_adaptive())
        except Exception as ex:
            print(f"[ERROR] ValidacionService.procesar — conectar BD: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error conectando a la base de datos", ex)
            except:
                pass
            raise

        try:
            try:
                from sqlalchemy import inspect
                inspector = inspect(db.bind)
                columnas = [c['name'] for c in inspector.get_columns('factura_pagos')]
                if 'tasa_cambio' not in columnas:
                    db.execute(text("ALTER TABLE factura_pagos ADD COLUMN tasa_cambio REAL"))
                    db.commit()
            except Exception as ex:
                print(f"[WARN] ALTER TABLE factura_pagos: {ex}")

            try:
                from sqlalchemy import inspect
                inspector = inspect(db.bind)
                columnas = [c['name'] for c in inspector.get_columns('facturas')]
                if 'tipo_documento' not in columnas:
                    db.execute(text("ALTER TABLE facturas ADD COLUMN tipo_documento TEXT DEFAULT 'Factura'"))
                    db.commit()
            except Exception as ex:
                print(f"[WARN] ALTER TABLE facturas (tipo_documento): {ex}")

            fecha_factura = data.get('fecha') or datetime.now()
            rif = data.get('rif', '')
            proveedor = data.get('proveedor') or 'Varios'
            tipo_documento = data.get('tipo_documento', 'Factura')

            proveedor_obj = None
            if proveedor and proveedor != "Varios":
                try:
                    proveedor_obj = db.query(Proveedor).filter(Proveedor.nombre == proveedor).first()
                    if not proveedor_obj:
                        try:
                            proveedor_obj = Proveedor(nombre=proveedor, rif=rif or "", estado="Activo")
                            db.add(proveedor_obj)
                            db.flush()
                            print(f"[NUEVO PROVEEDOR] Creado: {proveedor} (RIF: {rif or 'No prov'})")
                        except Exception as ex:
                            print(f"[WARN] Crear proveedor: {ex}")
                except Exception as ex:
                    print(f"[WARN] Buscar proveedor: {ex}")

            usuario_val = data.get('validada_por', 'Sistema')

            ref_fact = data.get('factura') or f"V-REF-{datetime.now().strftime('%H%M%S')}"

            try:
                existente = db.query(Factura).filter(Factura.numero_factura == ref_fact).first()
                if existente:
                    print(f"[WARN] Factura {ref_fact} ya existe, se vinculan las entradas")
                    movements_updated = db.query(Movimiento).filter(
                        Movimiento.id.in_(list(selected_entradas))
                    ).all()
                    for m in movements_updated:
                        m.factura_id = existente.id
                    db.commit()

                    # Reset sincronizado=0 so _upload_pending_movimientos picks them up
                    try:
                        from usr.database.local_replica import get_local_conn
                        c2 = get_local_conn()
                        for m in movements_updated:
                            c2.execute("UPDATE movimientos SET sincronizado = 0 WHERE id = ?", (m.id,))
                        c2.commit()
                        c2.close()
                    except Exception as ex:
                        print(f"[WARN] Reset sincronizado (dup): {ex}")

                    result = {
                        'factura_id': existente.id,
                        'movimientos_count': len(movements_updated),
                        'proveedor_obj': None,
                        'usuario': usuario_val
                    }

                    # Queue factura + payments + movement IDs for background sync
                    try:
                        from usr.database.sync_queue import SyncQueue as SyncQ
                        from datetime import datetime as dt_module

                        _s = lambda v: v.isoformat() if hasattr(v, 'isoformat') else str(v) if v else None
                        fact_data = {
                            'numero_factura': existente.numero_factura,
                            'proveedor': existente.proveedor,
                            'tipo_documento': existente.tipo_documento,
                            'fecha_factura': _s(existente.fecha_factura),
                            'fecha_recepcion': _s(existente.fecha_recepcion),
                            'total_bruto': existente.total_bruto,
                            'total_impuestos': existente.total_impuestos,
                            'total_neto': existente.total_neto,
                            'estado': existente.estado,
                            'validada_por': existente.validada_por,
                            'fecha_validacion': _s(existente.fecha_validacion),
                            'movimiento_ids': [m.id for m in movements_updated],
                        }
                        SyncQ.add_pending('facturas', 'update', fact_data)

                        for pago in data.get('pagos', []):
                            SyncQ.add_pending('factura_pagos', 'insert', {
                                'factura_numero': existente.numero_factura,
                                'tipo_pago': pago.get('tipo', ''),
                                'monto': pago.get('monto', 0) * pago.get('tasa', 1),
                                'referencia': pago.get('ref', ''),
                                'tasa_cambio': pago.get('tasa', 1) if pago.get('tipo') == 'divisas' else None,
                            })

                        if is_online():
                            from usr.database.sync import get_sync_manager
                            sm = get_sync_manager()
                            if sm:
                                sm.force_sync_now()
                    except Exception as ex:
                        print(f"[SYNC] Error encolando factura duplicada: {ex}")

                    db.close()
                    return result
            except Exception as ex:
                print(f"[ERROR] ValidacionService.procesar — buscar duplicado: {ex}")
                ref_fact = f"V-REF-{datetime.now().strftime('%H%M%S')}"

            try:
                monto_val = data.get('monto', 0)
                nueva_fac = Factura(
                    numero_factura=ref_fact,
                    proveedor=proveedor,
                    fecha_factura=fecha_factura,
                    fecha_recepcion=datetime.now(),
                    total_bruto=monto_val,
                    total_impuestos=0,
                    total_neto=monto_val,
                    estado="Validada",
                    validada_por=usuario_val,
                    fecha_validacion=datetime.now(),
                    tipo_documento=tipo_documento
                )
                db.add(nueva_fac)
                db.flush()
            except Exception as ex:
                print(f"[ERROR] ValidacionService.procesar — crear factura: {ex}")
                import traceback; traceback.print_exc()
                raise

            lista_pagos = data.get('pagos', [])
            for pago in lista_pagos:
                try:
                    tipo = pago.get('tipo', '')
                    monto_pago = pago.get('monto', 0)
                    tasa = pago.get('tasa', 1)
                    ref = pago.get('ref', '')
                    monto_ves = monto_pago * tasa

                    nuevo_pago = FacturaPago(
                        factura_id=nueva_fac.id,
                        tipo_pago=tipo,
                        monto=monto_ves,
                        referencia=ref,
                        tasa_cambio=tasa if tipo == 'divisas' else None
                    )
                    db.add(nuevo_pago)
                except Exception as ex:
                    print(f"[WARN] Agregar pago: {ex}")

            movements = db.query(Movimiento).filter(Movimiento.id.in_(list(selected_entradas))).all()
            for m in movements:
                m.factura_id = nueva_fac.id

            db.commit()

            # Reset sincronizado=0 on linked movements so _upload_pending_movimientos picks them up
            try:
                from usr.database.local_replica import get_local_conn
                c2 = get_local_conn()
                for m in movements:
                    c2.execute("UPDATE movimientos SET sincronizado = 0 WHERE id = ?", (m.id,))
                c2.commit()
                c2.close()
            except Exception as ex:
                print(f"[WARN] Reset sincronizado movements: {ex}")

            result = {
                'factura_id': nueva_fac.id,
                'movimientos_count': len(movements),
                'proveedor_obj': proveedor_obj,
                'usuario': usuario_val
            }

            # Queue to SyncQueue for background sync (works offline too)
            try:
                from usr.database.sync_queue import SyncQueue as SyncQ

                _serialize = lambda v: v.isoformat() if hasattr(v, 'isoformat') else str(v) if v else None

                fact_data = {
                    'numero_factura': nueva_fac.numero_factura,
                    'proveedor': nueva_fac.proveedor,
                    'tipo_documento': nueva_fac.tipo_documento,
                    'fecha_factura': _serialize(nueva_fac.fecha_factura),
                    'fecha_recepcion': _serialize(nueva_fac.fecha_recepcion),
                    'total_bruto': nueva_fac.total_bruto,
                    'total_impuestos': nueva_fac.total_impuestos,
                    'total_neto': nueva_fac.total_neto,
                    'estado': nueva_fac.estado,
                    'validada_por': nueva_fac.validada_por,
                    'fecha_validacion': _serialize(nueva_fac.fecha_validacion),
                    'movimiento_ids': [m.id for m in movements],
                }
                SyncQ.add_pending('facturas', 'insert', fact_data)

                for pago in lista_pagos:
                    pago_data = {
                        'factura_numero': nueva_fac.numero_factura,
                        'tipo_pago': pago.get('tipo', ''),
                        'monto': pago.get('monto', 0) * pago.get('tasa', 1),
                        'referencia': pago.get('ref', ''),
                        'tasa_cambio': pago.get('tasa', 1) if pago.get('tipo') == 'divisas' else None,
                    }
                    SyncQ.add_pending('factura_pagos', 'insert', pago_data)

                # Try immediate sync if online
                try:
                    if is_online():
                        from usr.database.sync import get_sync_manager
                        sm = get_sync_manager()
                        if sm:
                            sm.force_sync_now()
                            result['sync'] = True
                            print("[SYNC] Factura sincronizada inmediatamente")
                except Exception as ex:
                    print(f"[SYNC] Error en sync inmediato (queda en cola): {ex}")
                    result['sync'] = False
            except Exception as ex:
                print(f"[SYNC ERROR] Error encolando sync: {ex}")
                import traceback; traceback.print_exc()
                result['sync'] = False

            db.close()
            return result

        except Exception as ex:
            print(f"[ERROR] ValidacionService.procesar: {ex}")
            import traceback; traceback.print_exc()
            if db:
                try:
                    db.rollback()
                    db.close()
                except:
                    pass
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al procesar validación de facturas", ex)
            except:
                pass
            raise