from datetime import datetime
from sqlalchemy import create_engine, text
from usr.database.base import get_db_adaptive, is_online
from usr.models import Proveedor, Factura, Movimiento, FacturaPago
from config.config import get_settings


class ValidacionService:
    @staticmethod
    def procesar(data: dict, selected_entradas: set) -> dict:
        from usr.database.base import get_db_adaptive
        from usr.models import Proveedor, Factura, Movimiento, FacturaPago
        
        db = next(get_db_adaptive())
        
        try:
            db.execute(text("ALTER TABLE factura_pagos ADD COLUMN tasa_cambio REAL"))
            db.commit()
        except:
            pass
        
        fecha_factura = data.get('fecha_factura') or datetime.now()
        rif = data.get('rif', '')
        proveedor = data.get('proveedor', 'Varios')
        
        # Crear proveedor si es nuevo
        proveedor_obj = None
        if rif and proveedor != "Varios":
            proveedor_obj = db.query(Proveedor).filter(Proveedor.nombre == proveedor).first()
            if not proveedor_obj:
                try:
                    proveedor_obj = Proveedor(nombre=proveedor, rif=rif, estado="Activo")
                    db.add(proveedor_obj)
                    db.flush()
                    print(f"[NUEVO PROVEEDOR] Creado: {proveedor} (RIF: {rif})")
                except Exception as ex:
                    print(f"[ERROR PROVEEDOR] {ex}")
        
        nueva_fac = Factura(
            numero_factura=data.get('ref_factura') or f"V-REF-{datetime.now().strftime('%H%M%S')}",
            proveedor=proveedor,
            fecha_factura=fecha_factura,
            fecha_recepcion=datetime.now(),
            total_bruto=data.get('monto', 0),
            total_impuestos=0,
            total_neto=data.get('monto', 0),
            estado="Validada",
            validada_por=data.get('usuario', 'Sistema'),
            fecha_validacion=datetime.now()
        )
        db.add(nueva_fac)
        db.flush()
        
        # Guardar pagos
        lista_pagos = data.get('pagos', [])
        for pago in lista_pagos:
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
        
        # Actualizar movimientos
        movimientos = db.query(Movimiento).filter(Movimiento.id.in_(list(selected_entradas))).all()
        for m in movimientos:
            m.factura_id = nueva_fac.id
        
        db.commit()
        
        result = {
            'factura_id': nueva_fac.id,
            'movimientos_count': len(movimientos),
            'proveedor_obj': proveedor_obj
        }
        
        # Sync con Supabase
        if is_online():
            try:
                result['sync'] = True
                settings = get_settings()
                remote_engine = create_engine(settings.DATABASE_URL)
                
                with remote_engine.connect() as conn:
                    conn.execute(text("""
                        INSERT INTO facturas (numero_factura, proveedor, fecha_factura, fecha_recepcion, 
                            total_bruto, total_impuestos, total_neto, estado, validada_por, fecha_validacion)
                        VALUES (:numero, :proveedor, :fecha_factura, :fecha_recepcion, 
                                :bruto, :impuestos, :neto, :estado, :validada_por, :fecha_valid)
                    """), {
                        'numero': nueva_fac.numero_factura,
                        'proveedor': nueva_fac.proveedor,
                        'fecha_factura': nueva_fac.fecha_factura,
                        'fecha_recepcion': nueva_fac.fecha_recepcion,
                        'bruto': nueva_fac.total_bruto,
                        'impuestos': nueva_fac.total_impuestos,
                        'neto': nueva_fac.total_neto,
                        'estado': nueva_fac.estado,
                        'validada_por': nueva_fac.validada_por,
                        'fecha_valid': nueva_fac.fecha_validacion
                    })
                    
                    result['supabase_id'] = conn.execute(
                        text("SELECT id FROM facturas WHERE numero_factura = :num"),
                        {'num': nueva_fac.numero_factura}
                    ).fetchone()[0]
                
                remote_engine.dispose()
            except Exception as ex:
                print(f"[SYNC ERROR] {ex}")
                result['sync'] = False
        
        db.close()
        return result