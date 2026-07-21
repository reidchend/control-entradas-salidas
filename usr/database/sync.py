"""
Sincronización Bidireccional con SQLAlchemy - maneja conexión y offline para multi-dispositivo
Implementa estrategia de sumatoria de movimientos para resolver conflictos.
"""
import threading
import time
from datetime import datetime
from typing import Optional, List, Dict
from sqlalchemy import text
from config.config import get_settings

class SyncManager:
    def __init__(self, engine_getter):
        self._engine_getter = engine_getter
        self._session_local_getter = None
        self.is_online = False
        self._on_connection_change = None
        self._sync_thread = None
        self._stop_event = threading.Event()
        self._background_sync_enabled = False
        self._on_sync_complete_callbacks = []
        self._on_sync_complete = None  # Callback simple para sync completo
        self._on_sync_progress = None  # Callback(msg: str) para progreso visual
    
    def set_sync_progress_callback(self, callback):
        """Registra función a llamar con cada paso del sync (msg: str)."""
        self._on_sync_progress = callback
    
    def _log(self, msg: str):
        """Print + notificar progreso visual."""
        print(msg)
        if self._on_sync_progress:
            try:
                self._on_sync_progress(msg)
            except Exception:
                pass
    
    @property
    def engine(self):
        return self._engine_getter()
    
    def set_session_local_getter(self, session_getter):
        self._session_local_getter = session_getter
    
    def set_sync_complete_callback(self, callback):
        """Registra función a llamar cada vez que termina un sync."""
        self._on_sync_complete = callback
    
    def add_sync_callback(self, callback):
        """Registra un callback que se ejecuta cuando termina un sync."""
        if callback not in self._on_sync_complete_callbacks:
            self._on_sync_complete_callbacks.append(callback)
    
    def remove_sync_callback(self, callback):
        """Elimina un callback registrado."""
        if callback in self._on_sync_complete_callbacks:
            self._on_sync_complete_callbacks.remove(callback)
    
    def _notify_sync_complete(self):
        """Notifica a todos los callbacks registrados."""
        for callback in self._on_sync_complete_callbacks:
            try:
                callback()
            except Exception as e:
                self._log(f"[SYNC] Error en callback: {e}")
    
    def _get_session_maker(self):
        if self._session_local_getter:
            return self._session_local_getter()
        return None
    
    def _get_remote_session_maker(self):
        engine = self._create_remote_engine()
        return engine.connect
    
    def _create_remote_engine(self):
        from sqlalchemy import create_engine
        from config.config import get_settings
        url = get_settings().DATABASE_URL
        # Timeout de 15s para no bloquear si Supabase no responde
        if 'pg8000' in url:
            return create_engine(url, connect_args={'timeout': 15})
        return create_engine(url, connect_args={'connect_timeout': 15})
    
    def check_connection(self) -> bool:
        """Verifica si hay conexión a la base de datos remota."""
        try:
            engine = self._engine_getter()
            if engine:
                with engine.connect() as conn:
                    conn.execute(text("SELECT 1"))
                if not self.is_online and self._on_connection_change:
                    self._on_connection_change(True)
                self.is_online = True
                return True
        except Exception as e:
            pass
        
        if self.is_online and self._on_connection_change:
            self._on_connection_change(False)
        self.is_online = False
        return False
    
    def set_connection_callback(self, callback):
        self._on_connection_change = callback
    
    def full_sync(self) -> bool:
        """Realiza una sincronización completa: sube pendientes y descarga del servidor."""
        from .local_replica import LocalReplica
        
        if not self.check_connection():
            self._log("[SYNC] Sin conexión, usando datos locales")
            return False
        
        self._log("[SYNC] Iniciando sincronización completa...")
        
        # Cada paso es independiente: un fallo en uno no debe bloquear a los demás
        # (p.ej. un error subiendo movimientos no debe impedir la descarga/poda de
        #  requisiciones que ya fueron eliminadas en el servidor).
        try:
            # 1. Procesar cola de sync primero (facturas, pagos, etc.)
            #    Las facturas deben existir en Supabase antes de que los movimientos
            #    intenten referenciarlas via factura_id.
            self._process_sync_queue()
            
            # 2. Subir movimientos pendientes (sincronizado=0)
            #    Ahora las facturas ya existen en Supabase y podemos resolver
            #    factura_id local → remoto via numero_factura.
            self._upload_pending_movimientos()
            
            # 3. Descargar del servidor para alinear IDs
            self._download_all_from_server()
            LocalReplica.set_last_sync("full_sync", datetime.now().isoformat())
            self._log("[SYNC] Sincronización completa finalizada")
            download_ok = True
        except Exception as e:
            self._log(f"[SYNC] Error en sincronización: {e}")
            import traceback
            traceback.print_exc()
            try:
                from usr.error_handler import show_sync_error
                show_sync_error(f"Error de sincronización: {type(e).__name__}")
            except:
                pass
        
        # Notificar callback (siempre, para refrescar vistas) si la descarga fue bien
        if download_ok:
            if self._on_sync_complete:
                try:
                    self._on_sync_complete()
                except Exception as e:
                    self._log(f"[SYNC] Error en callback: {e}")
            
            try:
                from .sync_callbacks import notify_sync_complete as notify_global
                notify_global()
            except Exception as e:
                self._log(f"[SYNC] Error en notify_global: {e}")
        
        return download_ok
    
    def _upload_pending_movimientos(self) -> int:
        from .local_replica import LocalReplica
        from .conn import get_local_conn
        from sqlalchemy import create_engine
        from config.config import get_settings

        pending_movimientos = LocalReplica.get_movimientos_pendientes()
        if not pending_movimientos:
            self._log("[SYNC] No hay movimientos pendientes")
            return 0

        settings = get_settings()
        remote_engine = self._create_remote_engine()
        synced_count = 0

        # Mapa local_factura_id -> numero_factura para resolver el id remoto
        try:
            facturas_local = {f['id']: f.get('numero_factura') for f in LocalReplica.get_facturas()}
        except Exception:
            facturas_local = {}

        def resolver_factura_remota(conn, local_factura_id):
            """Convierte el id local de factura en el id remoto (Supabase)."""
            if not local_factura_id:
                return None
            num = facturas_local.get(local_factura_id)
            if not num:
                return None
            row = conn.execute(
                text("SELECT id FROM facturas WHERE numero_factura = :num"),
                {'num': num}
            ).fetchone()
            return row[0] if row else None

        try:
            with remote_engine.connect() as conn:
                for mov in pending_movimientos:
                    try:
                        mov_id = mov.get('id')
                        local_factura_id = mov.get('factura_id')

                        # Resolver factura_id local → remoto via numero_factura
                        remote_factura_id = None
                        if local_factura_id:
                            try:
                                local_conn = get_local_conn()
                                cur = local_conn.cursor()
                                cur.execute(
                                    "SELECT numero_factura FROM facturas WHERE id = ?",
                                    (local_factura_id,)
                                )
                                row = cur.fetchone()
                                local_conn.close()
                                if row:
                                    num_fact = row['numero_factura']
                                    result = conn.execute(
                                        text("SELECT id FROM facturas WHERE numero_factura = :num"),
                                        {'num': num_fact}
                                    ).fetchone()
                                    if result:
                                        remote_factura_id = result[0]
                            except Exception as ex:
                                print(f"[SYNC] Error resolviendo factura_id {local_factura_id}: {ex}")

                        # Buscar si el movimiento ya existe en Supabase por campos clave
                        match = conn.execute(text("""
                            SELECT id FROM movimientos 
                            WHERE producto_id = :p AND tipo = :t AND cantidad = :c
                            AND fecha_movimiento = :f AND almacen = :a
                            LIMIT 1
                        """), {
                            'p': mov.get('producto_id'),
                            't': mov.get('tipo'),
                            'c': mov.get('cantidad'),
                            'f': mov.get('fecha_movimiento'),
                            'a': mov.get('almacen'),
                        }).fetchone()

                        if match:
                            remote_mov_id = match[0]
                            if remote_factura_id:
                                conn.execute(
                                    text("UPDATE movimientos SET factura_id = :fid WHERE id = :id"),
                                    {'fid': remote_factura_id, 'id': remote_mov_id}
                                )
                                conn.commit()
                                print(f"[SYNC] Movimiento {mov_id} → factura_id={remote_factura_id} (remoto) actualizado (ID remoto: {remote_mov_id})")
                        else:
                            mov_data = {
                                'producto_id': mov.get('producto_id'),
                                'factura_id': remote_factura_id,
                                'tipo': mov.get('tipo'),
                                'cantidad': mov.get('cantidad'),
                                'cantidad_anterior': mov.get('cantidad_anterior', 0),
                                'cantidad_nueva': mov.get('cantidad_nueva', 0),
                                'peso_total': mov.get('peso_total', 0),
                                'peso_registrado': mov.get('peso_registrado'),
                                'foto_peso_url': mov.get('foto_peso_url'),
                                'registrado_por': mov.get('registrado_por'),
                                'observaciones': mov.get('observaciones'),
                                'almacen': mov.get('almacen'),
                                'fecha_movimiento': mov.get('fecha_movimiento'),
                            }
                            columns = ", ".join(mov_data.keys())
                            placeholders = ", ".join([f":{k}" for k in mov_data.keys()])
                            conn.execute(text(f"INSERT INTO movimientos ({columns}) VALUES ({placeholders})"), mov_data)
                            conn.commit()

                        # Si el movimiento tiene factura_id pero no se pudo resolver
                        # el ID remoto, no lo marcamos como sincronizado para reintentar
                        if local_factura_id and not remote_factura_id:
                            print(f"[SYNC] Movimiento {mov_id} postergado: factura_id={local_factura_id} no resuelto en Supabase")
                            continue

                        LocalReplica.mark_movimiento_sincronizado(mov_id)
                        synced_count += 1
                    except Exception as e:
                        self._log(f"[SYNC] Error al subir movimiento {mov.get('id')}: {e}")
        finally:
            remote_engine.dispose()

        self._log(f"[SYNC] {synced_count} movimientos subidos al servidor")
        return synced_count
    
    def _download_all_from_server(self) -> bool:
        """Descarga todos los datos del servidor y guarda en local."""
        from .local_replica import LocalReplica
        import json
        from datetime import datetime
        
        def serialize_value(val):
            """Convierte valores a formato serializable."""
            if val is None:
                return None
            if isinstance(val, datetime):
                return val.isoformat()
            if isinstance(val, (int, float, str, bool)):
                return val
            return str(val)
        
        def dict_to_serializable(row_dict):
            """Convierte un diccionario con valores complejos a serializables."""
            return {k: serialize_value(v) for k, v in row_dict.items()}
        
        tables_to_sync = [
            ('categorias', 'categorias'), 
            ('productos', 'productos'), 
            ('proveedores', 'proveedores'),
            ('existencias', 'existencias'), 
            ('movimientos', 'movimientos'), 
            ('facturas', 'facturas'), 
            ('factura_pagos', 'factura_pagos'),
            ('requisiciones', 'requisiciones'),
            ('movimientos_archivo', 'movimientos_archivo')
        ]
        
        from sqlalchemy import create_engine
        from config.config import get_settings
        settings = get_settings()
        remote_engine = self._create_remote_engine()
        
        with remote_engine.connect() as conn:
            # Migración remota: asegurar columna verificado en requisicion_detalles
            try:
                conn.execute(text("ALTER TABLE requisicion_detalles ADD COLUMN verificado INTEGER DEFAULT 0"))
                conn.commit()
            except Exception:
                conn.rollback()  # Resetear transacción para que SELECTs siguientes funcionen
            
            for local_table, server_table in tables_to_sync:
                try:
                    result = conn.execute(text(f"SELECT * FROM {server_table}"))
                    rows = result.fetchall()
                    data = [dict_to_serializable(dict(row._mapping)) for row in rows]
                    
                    remote_ids = [r['id'] for r in data if r.get('id') is not None]
                    
                    # Usar INSERT OR REPLACE para no perder datos locales sin sincronizar
                    if local_table == 'categorias':
                        LocalReplica.save_categorias(data)
                        LocalReplica.delete_orphaned_records('categorias', remote_ids, 'nombre')
                    elif local_table == 'productos':
                        LocalReplica.save_productos(data)
                        LocalReplica.delete_orphaned_records('productos', remote_ids, 'codigo')
                    elif local_table == 'proveedores':
                        LocalReplica.save_proveedores(data)
                        LocalReplica.delete_orphaned_records('proveedores', remote_ids, 'nombre')
                    elif local_table == 'existencias':
                        LocalReplica.save_existencias(data)
                    elif local_table == 'movimientos':
                        # Primero clear para evitar duplicados
                        LocalReplica.clear_movimientos()
                        LocalReplica.save_movimientos(data)
                    elif local_table == 'facturas':
                        LocalReplica.save_facturas(data)
                        LocalReplica.delete_orphaned_records('facturas', remote_ids, 'numero_factura')
                    elif local_table == 'factura_pagos':
                        LocalReplica.save_factura_pagos(data)
                        LocalReplica.delete_orphaned_records('factura_pagos', remote_ids)
                    elif local_table == 'requisiciones':
                        LocalReplica.save_requisiciones(data)
                    elif local_table == 'movimientos_archivo':
                        LocalReplica.clear_movimientos_archivo()
                        LocalReplica.save_movimientos_archivo(data)
                    
                    self._log(f"[SYNC] {len(data)} {local_table} baixats")




                except Exception as e:
                    self._log(f"[SYNC] Error descargando {local_table}: {e}")
        
        remote_engine.dispose()
        
        # Recalcular existencias después de la descarga
        LocalReplica.recalculate_existencias()
        self._log("[SYNC] Descarga completada")
        return True
    
    def start_background_sync(self, session_getter, interval_seconds: int = 20):
        """Inicia sincronización en segundo plano cada interval_seconds."""
        self._log(f"[SYNC] start_background_sync() llamado con interval={interval_seconds}s")
        if self._sync_thread and self._sync_thread.is_alive():
            self._log("[SYNC] Hilo ya está corriendo, no se inicia nuevo")
            return
        
        self._session_local_getter = session_getter
        self._stop_event.clear()
        self._background_sync_enabled = True
        self._sync_thread = threading.Thread(
            target=self._background_sync_loop,
            args=(interval_seconds,),
            daemon=True
        )
        self._sync_thread.start()
        self._log(f"[SYNC] Sync en segundo plano iniciado (intervalo: {interval_seconds}s)")
    
    def stop_background_sync(self):
        self._stop_event.set()
        self._background_sync_enabled = False
        if self._sync_thread:
            self._sync_thread.join(timeout=2)
        self._log("[SYNC] Sync en segundo plano detenido")
    
    def _background_sync_loop(self, interval):
        """Loop de sync en background."""
        from .sync_callbacks import notify_sync_complete as notify_global
        
        while not self._stop_event.is_set():
            try:
                if self.check_connection():
                    # 1. Procesar cola de sync primero (facturas deben existir en Supabase)
                    self._process_sync_queue()
                    # 2. Subir movimientos pendientes (pueden referenciar facturas ya subidas)
                    self._upload_pending_movimientos()
                    # 3. Descargar cambios del servidor
                    self._download_all_from_server()
                    self._notify_sync_complete()
                    notify_global()
            except Exception as e:
                self._log(f"[SYNC] Error descargando (loop): {e}")
            
            self._stop_event.wait(interval)
    
    def _process_sync_queue(self):
        """Procesa la cola de sync - sube pendientes y descarga cambios."""
        from .sync_queue import get_sync_queue
        from .local_replica import LocalReplica
        
        # Verificar conexión antes de procesar
        if not self.check_connection():
            self._log("[SYNC] Sin conexión, saltando procesamiento de cola")
            return
        
        queue = get_sync_queue()
        
        pending = queue.get_pending()
        
        # Los movimientos se sincronizan via _upload_pending_movimientos (sincronizado=0),
        # excepto las eliminaciones que van por sync_queue con operation='delete'
        pending = [p for p in pending if not (p.get('table_name') == 'movimientos' and p.get('operation') != 'delete')]
        
        if pending:
            # Usar conexión a Supabase para subir datos
            from sqlalchemy import create_engine
            from config.config import get_settings
            settings = get_settings()
            remote_engine = self._create_remote_engine()
            
            try:
                uploaded = self._upload_to_remote(remote_engine, pending)
                self._log(f"[SYNC] {uploaded} operaciones subidas a Supabase")
            except Exception as e:
                self._log(f"[SYNC] Error al subir a Supabase: {e}")
            finally:
                remote_engine.dispose()
        
        queue.set_last_sync(datetime.now().isoformat())
        self._log("[SYNC] Ciclo de sync completado")
    
    def _upload_to_remote(self, remote_engine, pending_items) -> int:
        """Sube elementos de la cola a Supabase usando SQL directo."""
        import json
        from .sync_queue import get_sync_queue
        
        queue = get_sync_queue()
        uploaded = 0
        
        with remote_engine.connect() as conn:
            for item in pending_items:
                table = None
                try:
                    data = json.loads(item['data'])
                    table = item['table_name']
                    operation = item['operation']
                    
                    if table == 'categorias':
                        # Determinar si es insert o update
                        has_nombre = 'nombre' in data and data.get('nombre')
                        has_id = 'id' in data and data.get('id')
                        
                        if has_nombre:
                            cols = ['nombre', 'descripcion', 'color', 'activo', 'updated_at']
                            vals = {
                                'nombre': data.get('nombre'),
                                'descripcion': data.get('descripcion', ''),
                                'color': data.get('color', '#888888'),
                                'activo': data.get('activo', 1),
                                'updated_at': data.get('updated_at')
                            }
                            
                            # Upsert por nombre
                            check_sql = text("SELECT id FROM categorias WHERE nombre = :nombre")
                            existing = conn.execute(check_sql, {'nombre': vals['nombre']}).fetchone()
                            
                            if existing:
                                set_cols = ", ".join([f"{k} = :{k}" for k in vals.keys()])
                                sql = text(f"UPDATE categorias SET {set_cols} WHERE nombre = :nombre")
                            else:
                                cols_str = ", ".join(vals.keys())
                                placeholders = ", ".join([f":{k}" for k in vals.keys()])
                                sql = text(f"INSERT INTO categorias ({cols_str}) VALUES ({placeholders})")
                        elif has_id:
                            # Update por ID (ej: desactivar)
                            vals = {
                                'id': data.get('id'),
                                'activo': data.get('activo', 0),
                                'updated_at': data.get('updated_at')
                            }
                            sql = text("UPDATE categorias SET activo = :activo, updated_at = :updated_at WHERE id = :id")
                        else:
                            continue
                        
                        conn.execute(sql, vals)
                        conn.commit()
                        
                        # Verificar que sepersistió antes de marcar completado
                        verify = conn.execute(check_sql, {'nombre': vals['nombre']}).fetchone()
                        if verify:
                            queue.mark_completed(item['id'])
                            uploaded += 1
                            self._log(f"[SYNC] Categoría sincronizada")
                        else:
                            raise Exception("Error: Categoría no encontrada tras commit")
                        
                    elif table == 'productos':
                        # Determinar si es insert o update
                        has_codigo = 'codigo' in data and data.get('codigo')
                        has_id = 'id' in data and data.get('id')
                        
                        vals = None  # Inicializar
                        
                        if has_codigo:
                            vals = {
                                 'nombre': data.get('nombre'),
                                 'codigo': data.get('codigo'),
                                 'descripcion': data.get('descripcion', ''),
                                 'categoria_id': int(data.get('categoria_id')) if data.get('categoria_id') else None,
                                 'es_pesable': data.get('es_pesable', 0),
                                 'requiere_foto_peso': data.get('requiere_foto_peso', 0),
                                 'peso_unitario': float(data.get('peso_unitario', 0)),
                                 'unidad_medida': data.get('unidad_medida', 'unidad'),
                                 'stock_actual': float(data.get('stock_actual', 0)),
                                 'stock_minimo': float(data.get('stock_minimo', 0)),
                                 'activo': data.get('activo', 1),
                                 'almacen_predeterminado': data.get('almacen_predeterminado', 'principal'),
                                 'tipo': data.get('tipo', 'ninguno'),
                                 'updated_at': data.get('updated_at')
                             }
                            
                            # Upsert por código
                            check_sql = text("SELECT id FROM productos WHERE codigo = :codigo")
                            existing = conn.execute(check_sql, {'codigo': vals['codigo']}).fetchone()
                            
                            if existing:
                                set_cols = ", ".join([f"{k} = :{k}" for k in vals.keys()])
                                sql = text(f"UPDATE productos SET {set_cols} WHERE codigo = :codigo")
                            else:
                                cols_str = ", ".join(vals.keys())
                                placeholders = ", ".join([f":{k}" for k in vals.keys()])
                                sql = text(f"INSERT INTO productos ({cols_str}) VALUES ({placeholders})")
                        elif has_id:
                            # Update por ID (ej: desactivar)
                            vals = {
                                'id': data.get('id'),
                                'activo': data.get('activo', 0),
                                'updated_at': data.get('updated_at')
                            }
                            sql = text("UPDATE productos SET activo = :activo, updated_at = :updated_at WHERE id = :id")
                        else:
                            continue
                        
                        conn.execute(sql, vals)
                        conn.commit()
                        queue.mark_completed(item['id'])
                        uploaded += 1
                        self._log(f"[SYNC] Producto sincronizado")
                    
                    elif table == 'movimientos' and operation == 'insert':
                        mov_data = {k: v for k, v in data.items() 
                                   if k not in ('sincronizado', 'created_at')}
# Quitar ID local para que Supabase genere uno nuevo
                        mov_data.pop('id', None)
                        
                        cols = ", ".join(mov_data.keys())
                        vals = ", ".join([f":{k}" for k in mov_data.keys()])
                        sql = text(f"INSERT INTO movimientos ({cols}) VALUES ({vals})")
                        conn.execute(sql, mov_data)
                        conn.commit()
                        
                        # Verificar conexión activa
                        conn.execute(text("SELECT 1")).fetchone()
                        queue.mark_completed(item['id'])
                        uploaded += 1
                        self._log(f"[SYNC] Movimiento sincronizado")
                    
                    elif table == 'movimientos' and operation == 'delete':
                        # Eliminar movimiento por campos coincidentes (ID local != ID remoto)
                        match_cond = "1=1"
                        match_params = {}
                        for key in ('producto_id', 'tipo', 'cantidad', 'fecha_movimiento', 'almacen'):
                            val = data.get(key)
                            if val is not None:
                                match_cond += f" AND {key} = :{key}"
                                match_params[key] = val
                        if match_params:
                            conn.execute(text(f"DELETE FROM movimientos WHERE {match_cond}"), match_params)
                            conn.commit()
                            queue.mark_completed(item['id'])
                            uploaded += 1
                            self._log(f"[SYNC] Movimiento eliminado en Supabase")
                        else:
                            self._log(f"[SYNC] WARN: delete movimiento sin datos coincidentes — {data}")
                    
                    elif table == 'facturas':
                        num_fact = data.get('numero_factura')
                        if not num_fact:
                            continue
                        
                        check = conn.execute(
                            text("SELECT id FROM facturas WHERE numero_factura = :num"),
                            {'num': num_fact}
                        ).fetchone()
                        
                        if check:
                            remote_id = check[0]
                            conn.execute(text("""
                                UPDATE facturas SET
                                    proveedor = :proveedor,
                                    fecha_factura = :fecha_factura,
                                    fecha_recepcion = :fecha_recepcion,
                                    total_bruto = :bruto,
                                    total_neto = :neto,
                                    estado = :estado,
                                    validada_por = :validada_por,
                                    fecha_validacion = :fecha_valid
                                WHERE id = :id
                            """), {
                                'proveedor': data.get('proveedor'),
                                'fecha_factura': data.get('fecha_factura'),
                                'fecha_recepcion': data.get('fecha_recepcion'),
                                'bruto': data.get('total_bruto'),
                                'neto': data.get('total_neto'),
                                'estado': data.get('estado'),
                                'validada_por': data.get('validada_por'),
                                'fecha_valid': data.get('fecha_validacion'),
                                'id': remote_id
                            })
                        else:
                            result_insert = conn.execute(text("""
                                INSERT INTO facturas (numero_factura, proveedor, fecha_factura, fecha_recepcion,
                                    total_bruto, total_impuestos, total_neto, estado, validada_por, fecha_validacion)
                                VALUES (:numero, :proveedor, :fecha_factura, :fecha_recepcion,
                                        :bruto, :impuestos, :neto, :estado, :validada_por, :fecha_valid)
                                RETURNING id
                            """), {
                                'numero': num_fact,
                                'proveedor': data.get('proveedor'),
                                'fecha_factura': data.get('fecha_factura'),
                                'fecha_recepcion': data.get('fecha_recepcion'),
                                'bruto': data.get('total_bruto'),
                                'impuestos': data.get('total_impuestos', 0),
                                'neto': data.get('total_neto'),
                                'estado': data.get('estado', 'Validada'),
                                'validada_por': data.get('validada_por'),
                                'fecha_valid': data.get('fecha_validacion'),
                            })
                            remote_id = result_insert.fetchone()[0]
                        
                        conn.commit()
                        
                        # Los movimientos se vinculan via _upload_pending_movimientos()
                        # que resuelve factura_id local → remoto por numero_factura
                        
                        queue.mark_completed(item['id'])
                        uploaded += 1
                        self._log(f"[SYNC] Factura {num_fact} sincronizada (ID remoto: {remote_id})")
                    
                    elif table == 'factura_pagos':
                        fact_num = data.get('factura_numero')
                        if not fact_num:
                            continue
                        
                        fact_check = conn.execute(
                            text("SELECT id FROM facturas WHERE numero_factura = :num"),
                            {'num': fact_num}
                        ).fetchone()
                        
                        if fact_check:
                            remote_fact_id = fact_check[0]
                            conn.execute(text("""
                                INSERT INTO factura_pagos (factura_id, tipo_pago, monto, referencia, tasa_cambio)
                                VALUES (:factura_id, :tipo, :monto, :ref, :tasa)
                            """), {
                                'factura_id': remote_fact_id,
                                'tipo': data.get('tipo_pago', ''),
                                'monto': data.get('monto', 0),
                                'ref': data.get('referencia', ''),
                                'tasa': data.get('tasa_cambio'),
                            })
                            conn.commit()
                        
                        queue.mark_completed(item['id'])
                        uploaded += 1
                        self._log(f"[SYNC] Pago de factura {fact_num} sincronizado")
                        
                    elif table == 'requisiciones':
                        if operation == 'delete':
                            num = data.get('numero')
                            if num:
                                # 1. Obtener el ID remoto usando el numero
                                res = conn.execute(
                                    text("SELECT id FROM requisiciones WHERE numero = :num"),
                                    {'num': num}
                                ).fetchone()
                                
                                if res:
                                    remote_id = res[0]
                                    # 2. Borrar primero los detalles para evitar errores de FK
                                    conn.execute(
                                        text("DELETE FROM requisicion_detalles WHERE requisicion_id = :rid"),
                                        {'rid': remote_id}
                                    )
                                    # 3. Borrar la requisición
                                    conn.execute(
                                        text("DELETE FROM requisiciones WHERE id = :id"),
                                        {'id': remote_id}
                                    )
                                    conn.commit()
                                    queue.mark_completed(item['id'])
                                    uploaded += 1
                                    self._log(f"[SYNC] Requisición {num} y sus detalles eliminados en Supabase")
                                else:
                                    # Si no existe en el servidor, marcamos como completado igualmente
                                    queue.mark_completed(item['id'])
                                    uploaded += 1
                                    self._log(f"[SYNC] Requisición {num} no encontrada en servidor, marcada como eliminada")
                            else:
                                self._log(f"[SYNC] Error: No se proporcionó número para eliminar requisición")
                                queue.mark_completed(item['id'])
                            continue

                        num = data.get('numero')
                        if not num:
                            continue
                        
                        req_vals = {
                            'numero': num,
                            'numero_secuencial': int(data.get('numero_secuencial') or 0),
                            'origen': data.get('origen'),
                            'destino': data.get('destino'),
                            'estado': data.get('estado', 'pendiente'),
                            'observaciones': data.get('observaciones'),
                            'creada_por': data.get('creada_por'),
                            'procesada_por': data.get('procesada_por'),
                            'fecha_procesamiento': data.get('fecha_procesamiento'),
                            'fecha_creacion': data.get('fecha_creacion'),
                            'actualizada': data.get('actualizada'),
                        }
                        
                        check = conn.execute(
                            text("SELECT id FROM requisiciones WHERE numero = :num"),
                            {'num': num}
                        ).fetchone()
                        
                        if check:
                            remote_id = check[0]
                            set_cols = ", ".join([f"{k} = :{k}" for k in req_vals.keys()])
                            conn.execute(
                                text(f"UPDATE requisiciones SET {set_cols} WHERE numero = :num"),
                                req_vals | {'num': num}
                            )
                        else:
                            cols = ", ".join(req_vals.keys())
                            ph = ", ".join([f":{k}" for k in req_vals.keys()])
                            res = conn.execute(
                                text(f"INSERT INTO requisiciones ({cols}) VALUES ({ph}) RETURNING id"),
                                req_vals
                            )
                            remote_id = res.fetchone()[0]
                        conn.commit()
                        
                        # Reemplazar detalles en el servidor
                        conn.execute(
                            text("DELETE FROM requisicion_detalles WHERE requisicion_id = :rid"),
                            {'rid': remote_id}
                        )
                        for det in data.get('detalles', []):
                            conn.execute(text("""
                                INSERT INTO requisicion_detalles
                                (requisicion_id, producto_id, ingrediente, cantidad, unidad, cantidad_surtida)
                                VALUES (:requisicion_id, :producto_id, :ingrediente, :cantidad, :unidad, :cantidad_surtida)
                            """), {
                                'requisicion_id': remote_id,
                                'producto_id': det.get('producto_id'),
                                'ingrediente': det.get('ingrediente'),
                                'cantidad': det.get('cantidad', 0),
                                'unidad': det.get('unidad', 'unidad'),
                                'cantidad_surtida': det.get('cantidad_surtida', 0),
                            })
                        conn.commit()
                        
                        # Mapear id local -> remoto para no duplicar ni perder la requisición
                        local_id = data.get('id')
                        if local_id and local_id != remote_id:
                            try:
                                from .local_replica import LocalReplica
                                LocalReplica.remap_requisicion_id(local_id, remote_id)
                            except Exception as e:
                                self._log(f"[SYNC] Error mapeando id de requisición: {e}")
                        
                        queue.mark_completed(item['id'])
                        uploaded += 1
                        self._log(f"[SYNC] Requisición {num} sincronizada (ID remoto: {remote_id})")
                    
                    elif table == 'requisicion_detalles' and operation == 'update':
                        verificado = 1 if data.get('verificado') else 0
                        det_id = data.get('id')
                        req_id = data.get('requisicion_id')
                        prod_id = data.get('producto_id')
                        ingred = data.get('ingrediente')
                        cant = data.get('cantidad')
                        
                        matched = False
                        # Intentar por id (registros ya existentes en Supabase)
                        if det_id:
                            res = conn.execute(
                                text("SELECT id FROM requisicion_detalles WHERE id = :id"),
                                {'id': det_id}
                            ).fetchone()
                            if res:
                                conn.execute(
                                    text("UPDATE requisicion_detalles SET verificado = :v WHERE id = :id"),
                                    {'v': verificado, 'id': det_id}
                                )
                                conn.commit()
                                matched = True
                        
                        if not matched and req_id and prod_id and ingred:
                            # Fallback: buscar por requisicion_id + producto_id + ingrediente + cantidad
                            res = conn.execute(
                                text("""SELECT id FROM requisicion_detalles 
                                    WHERE requisicion_id = :rid AND producto_id = :pid 
                                    AND ingrediente = :ing AND cantidad = :cant"""),
                                {'rid': req_id, 'pid': prod_id, 'ing': ingred, 'cant': cant}
                            ).fetchone()
                            if res:
                                conn.execute(
                                    text("UPDATE requisicion_detalles SET verificado = :v WHERE id = :id"),
                                    {'v': verificado, 'id': res[0]}
                                )
                                conn.commit()
                                matched = True
                        
                        if matched:
                            queue.mark_completed(item['id'])
                            uploaded += 1
                            self._log(f"[SYNC] Detalle requisición verificado={verificado} sincronizado")
                        else:
                            self._log(f"[SYNC] No se encontró detalle de requisición en Supabase para actualizar verificado")
                    
                    elif table == 'kardex_validaciones' and operation == 'insert':
                        reg_data = {
                            'producto_id': data.get('producto_id'),
                            'requisicion_id': data.get('requisicion_id'),
                            'fecha': data.get('fecha'),
                            'usuario': data.get('usuario'),
                            'cantidad_fisica': data.get('cantidad_fisica'),
                            'observacion': data.get('observacion'),
                        }
                        conn.execute(text("""
                            INSERT INTO kardex_validaciones
                            (producto_id, requisicion_id, fecha, usuario, cantidad_fisica, observacion)
                            VALUES (:producto_id, :requisicion_id, :fecha, :usuario, :cantidad_fisica, :observacion)
                        """), reg_data)
                        conn.commit()
                        queue.mark_completed(item['id'])
                        uploaded += 1
                        self._log(f"[SYNC] Kardex validación sincronizada")
                        
                except Exception as e:
                    try:
                        conn.rollback()  # Reset transacción para que el siguiente item funcione
                    except:
                        pass
                    queue.mark_failed(item['id'], str(e))
                    self._log(f"[SYNC] Error subiendo {table}: {e}")
        
        return uploaded
    
    def get_connection_status(self) -> dict:
        """Estado de conexión y sincronización."""
        from .sync_queue import SyncQueue
        
        pending = SyncQueue.get_pending(limit=100)
        last = SyncQueue.get_last_sync()
        
        return {
            "online": self.is_online,
            "pending_count": len(pending),
            "last_sync": last,
            "background_enabled": self._background_sync_enabled
        }
    
    def force_sync_now(self) -> bool:
        """Fuerza una sincronización inmediata."""
        return self.full_sync()


def save_movimiento_with_sync(movimiento_data: dict, update_local: bool = True) -> bool:
    """
    Guarda un movimiento en local y opcionalmente lo sincroniza.
    Retorna True si se guardó localmente.
    """
    from datetime import datetime
    from sqlalchemy import text
    from .local_replica import LocalReplica
    
    movimiento_data['fecha_movimiento'] = datetime.now().isoformat()
    movimiento_data['created_at'] = datetime.now().isoformat()
    movimiento_data['sincronizado'] = False
    
    local_id = LocalReplica.save_movimiento(movimiento_data)
    print(f"[OFFLINE] Movimiento guardado localmente con ID: {local_id}")
    
    sync_mgr = get_sync_manager()
    if sync_mgr and sync_mgr.check_connection():
        try:
            remote_engine = sync_mgr._create_remote_engine()
            try:
                mov_clean = {k: v for k, v in movimiento_data.items() 
                           if k not in ('sincronizado', 'created_at')}
                cols = ", ".join(mov_clean.keys())
                vals = ", ".join([f":{k}" for k in mov_clean.keys()])
                sql = text(f"INSERT INTO movimientos ({cols}) VALUES ({vals})")
                with remote_engine.connect() as conn:
                    conn.execute(sql, mov_clean)
                    conn.commit()
                remote_engine.dispose()
                LocalReplica.mark_movimiento_sincronizado(local_id)
                print("[OFFLINE] Movimiento sincronizado inmediatamente")
                return True
            except Exception as e:
                if remote_engine:
                    remote_engine.dispose()
                print(f"[OFFLINE] Error al syncar inmediatamente: {e}")
        except Exception as e:
            print(f"[OFFLINE] Error creando engine: {e}")
    
    return False


def recalculate_local_stock():
    """Recalcula las existencias locales desde los movimientos."""
    from .local_replica import LocalReplica
    LocalReplica.recalculate_existencias()


def get_pending_movimientos_count() -> int:
    """Obtiene el número de movimientos pendientes de sincronización."""
    from .local_replica import LocalReplica
    return len(LocalReplica.get_movimientos_pendientes())


_sync_manager: Optional[SyncManager] = None

def init_sync_manager(engine_getter) -> SyncManager:
    global _sync_manager
    _sync_manager = SyncManager(engine_getter)
    return _sync_manager

def get_sync_manager() -> Optional[SyncManager]:
    return _sync_manager
