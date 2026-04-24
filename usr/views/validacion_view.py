import flet as ft
from datetime import datetime
from sqlalchemy import create_engine, text
from usr.database.base import get_db, get_db_adaptive, is_online
from usr.models import Movimiento, Factura,Producto, Categoria, Existencia
from usr.logger import get_logger
from usr.theme import get_theme, get_colors
from config.config import get_settings

logger = get_logger(__name__)


def _fmt_datetime(dt):
    if dt is None:
        return "Sin fecha"
    try:
        return dt.strftime("%d/%m %H:%M")
    except:
        return "Sin fecha"


def _colors(page):
    return get_colors(page)


class ValidacionView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.padding = ft.padding.only(left=10, right=10, bottom=16, top=8)
        self.bgcolor = '#1A1A1A'
        
        self.entradas_list = ft.ListView(expand=True, spacing=10, padding=ft.padding.only(top=10))
        self.search_field = None
        self.selected_entradas = set()
        self.entradas_data = {}
        self.is_loading = False
        self.active_dialog = None
        
        self.validate_button = None
        self.clear_button = None
        
        self._build_ui()

    def _update_connection_indicator(self):
        if not hasattr(self, '_connection_indicator'):
            return
        
        try:
            online = is_online()
            icon = ft.Icons.WIFI if online else ft.Icons.WIFI_OFF
            color = ft.Colors.GREEN_400 if online else ft.Colors.RED_400
            tooltip = "Conectado" if online else "Sin conexión"
            
            self._connection_indicator.content = ft.Icon(icon, color=color, size=18)
            self._connection_indicator.tooltip = tooltip
            
            if self.page and self._connection_indicator.page:
                self._connection_indicator.update()
        except:
            pass

    def did_mount(self):
        self._build_ui()
        if self.page and self.page.client_storage:
            self._load_entradas_pendientes()
        
        self._update_connection_indicator()
        
        import threading
        import time
        
        def check_connection_loop():
            while True:
                time.sleep(10)
                if hasattr(self, 'page') and self.page:
                    self._update_connection_indicator()
                    try:
                        self.page.update()
                    except:
                        pass
        
        self._connection_thread = threading.Thread(target=check_connection_loop, daemon=True)
        self._connection_thread.start()

    def _build_ui(self):
        colors = _colors(self.page)
        
        self._connection_indicator = ft.Container(
            content=ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18),
            tooltip="Conectado",
            padding=5,
            on_click=self._on_sync_indicator_click
        )
        
        header = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Column([
                        ft.Text("Validación", size=26, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                        ft.Text("Vincular entradas a facturas", size=13, color=colors['text_secondary']),
                    ], expand=True, spacing=0),
                    self._connection_indicator,
                    ft.IconButton(
                        ft.Icons.REFRESH_ROUNDED,
                        on_click=lambda _: self._load_entradas_pendientes(),
                        icon_color=colors['text_secondary'],
                    )
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            ], spacing=0),
            padding=ft.padding.only(bottom=10)
        )
        
        self.search_field = ft.TextField(
            hint_text="Buscar...",
            prefix_icon=ft.Icons.SEARCH_ROUNDED,
            border_radius=12,
            border_color=colors['input_border'],
            focused_border_color=colors['accent'],
            height=45,
            expand=1,
            on_change=lambda _: self._load_entradas_pendientes()
        )
        
        self.validate_button = ft.ElevatedButton(
            "Validar seleccionadas",
            bgcolor=ft.Colors.BLUE_600,
            color="white",
            disabled=True,
            on_click=self._show_validar_dialog
        )
        
        self.clear_button = ft.ElevatedButton(
            "Limpiar selección",
            bgcolor=ft.Colors.ORANGE_600,
            color="white",
            disabled=True,
            on_click=lambda _: self._clear_selection()
        )
        
        controls_section = ft.Container(
            content=ft.Column([
                self.search_field,
                ft.Row(
                    [self.validate_button, self.clear_button], 
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN
                )
            ], spacing=10),
            padding=ft.padding.symmetric(horizontal=20, vertical=10),
        )
        
        self.content = ft.Column([
            header,
            controls_section,
            self.entradas_list
        ], spacing=0, expand=True)

    def _on_sync_indicator_click(self, e=None):
        from usr.database import get_sync_manager, get_pending_movimientos_count
        
        sync_mgr = get_sync_manager()
        if not sync_mgr or not self.page:
            return
        
        self._update_connection_indicator()
        self.page.update()

    def _toggle_entrada_selection(self, entrada_id):
        if entrada_id in self.selected_entradas:
            self.selected_entradas.discard(entrada_id)
        else:
            self.selected_entradas.add(entrada_id)
        
        self._update_validate_button_state()
        
        if entrada_id in self.entradas_data:
            card, check_icon = self.cards_dict.get(entrada_id, (None, None))
            if card and check_icon:
                is_selected = entrada_id in self.selected_entradas
                check_icon.name = ft.Icons.CHECK_CIRCLE_ROUNDED if is_selected else ft.Icons.RADIO_BUTTON_UNCHECKED_ROUNDED
                check_icon.color = _colors(self.page)['accent'] if is_selected else _colors(self.page)['text_hint']
                card.bgcolor = _colors(self.page)['card_hover'] if is_selected else _colors(self.page)['card']
                card.update()

    def _update_validate_button_state(self):
        has_selection = len(self.selected_entradas) > 0
        self.validate_button.disabled = not has_selection
        self.clear_button.disabled = not has_selection
        if has_selection:
            self.validate_button.text = f"Validar {len(self.selected_entradas)} entradas"
        else:
            self.validate_button.text = "Validar seleccionadas"
        self.validate_button.update()
        self.clear_button.update()

    def _clear_selection(self):
        self.selected_entradas.clear()
        self._update_validate_button_state()
        self._load_entradas_pendientes()

    def _load_entradas_pendientes(self):
        if self.is_loading:
            return

        self.is_loading = True

        db = None
        try:
            self.entradas_list.controls = [ft.ProgressBar(color="blue")]
            self.update()
            db = next(get_db_adaptive())
            query = db.query(Movimiento).filter(
                Movimiento.tipo == "entrada",
                Movimiento.factura_id.is_(None)
            )
            
            search_term = ""
            if self.search_field and hasattr(self.search_field, 'value') and self.search_field.value:
                search_term = self.search_field.value.lower().strip()
            
            if search_term:
                query = query.join(Producto).filter(Producto.nombre.ilike(f"%{search_term}%"))
            
            entradas = query.order_by(Movimiento.fecha_movimiento.desc()).all()
            self.entradas_data = {e.id: e for e in entradas}
            
            self.entradas_list.controls.clear()
            if not entradas:
                self.entradas_list.controls.append(
                    ft.Container(
                        content=ft.Column([
                            ft.Icon(ft.Icons.FACT_CHECK_OUTLINED, size=50, color=ft.Colors.GREY_300),
                            ft.Text("Sin entradas pendientes", color=ft.Colors.GREY_400)
                        ], horizontal_alignment="center"),
                        padding=ft.padding.only(top=100),
                        alignment="center"
                    )
                )
            else:
                self.cards_dict = {}
                for ent in entradas:
                    self.entradas_card = self._create_entrada_card(ent)
                    self.entradas_list.controls.append(self.entradas_card)
            
            self._update_validate_button_state()
            if self.page and self.page.client_storage: self.page.update()
        except Exception as ex:
            logger.error(f"Error cargando entradas: {ex}")
            import traceback
            traceback.print_exc()
            self.entradas_list.controls = [ft.Text(f"Error: {str(ex)}")]
        finally:
            if db:
                db.close()
            self.is_loading = False

    def _create_entrada_card(self, entrada: Movimiento):
        is_selected = entrada.id in self.selected_entradas
        colors = _colors(self.page)
        
        almacen_nombre = getattr(entrada, 'almacen', None) or 'principal'
        almacen_badge = ft.Text(
            f"📦 {almacen_nombre.title()}",
            size=10,
            color=colors['text_secondary'],
        )

        es_pesable = getattr(entrada.producto, 'es_pesable', False) if entrada.producto else False
        
        peso_valor = getattr(entrada, "peso_total", 0) or 0
        
        if es_pesable and peso_valor > 0:
            cantidad_texto = f"{peso_valor:.3f} kg"
            peso_badge = ft.Text()
        else:
            cantidad_texto = f"{entrada.cantidad} {entrada.producto.unidad_medida if entrada.producto else 'uds'}"
            peso_badge = ft.Text()
            if peso_valor > 0.001:
                peso_badge = ft.Text(
                    f"⚖️ {peso_valor:.3f} kg",
                    size=10,
                    color='#FF9800',
                )

        check_icon = ft.Icon(
            ft.Icons.CHECK_CIRCLE_ROUNDED if is_selected else ft.Icons.RADIO_BUTTON_UNCHECKED_ROUNDED,
            color=colors['accent'] if is_selected else colors['text_hint'],
            size=22
        )

        def on_eliminar(e):
            self._eliminar_entrada(entrada)
        
        card = ft.Container(
            content=ft.Row([
                ft.Container(content=check_icon, padding=2),
                ft.Column([
                    ft.Text(
                        entrada.producto.nombre if entrada.producto else "Producto sin nombre",
                        weight=ft.FontWeight.BOLD, size=15, color=colors['text_primary'],
                        max_lines=1, overflow=ft.TextOverflow.ELLIPSIS
                    ),
                    ft.Row([
                        ft.Text(cantidad_texto, size=13, weight="w600", color=colors['success']),
                        peso_badge,
                        ft.Container(expand=True),
                        ft.Text(
                            entrada.fecha_movimiento.strftime("%d/%m %H:%M") 
                            if entrada.fecha_movimiento else "Sin fecha",
                            size=11, 
                            color=colors['text_secondary']
                        ),
                    ], spacing=8, vertical_alignment="center"),
                    almacen_badge,
                ], expand=True, spacing=2),
                ft.IconButton(
                    icon=ft.Icons.DELETE_OUTLINE_ROUNDED,
                    icon_color=colors['error'],
                    tooltip="Eliminar entrada",
                    on_click=on_eliminar,
                )
            ], spacing=8),
            padding=15,
            animate=200,
            bgcolor=colors['card_hover'] if is_selected else colors['card'],
            border_radius=12,
            border=ft.border.all(2, colors['accent']) if is_selected else ft.border.all(1, colors['border']),
            on_click=lambda _: self._toggle_entrada_selection(entrada.id)
        )
        
        self.cards_dict[entrada.id] = (card, check_icon)
        return card

    def _eliminar_entrada(self, entrada):
        from sqlalchemy import text
        from config.config import get_settings
        from usr.database.base import is_online
        from usr.database.sync_queue import get_sync_queue
        
        def on_confirmar(e):
            db = next(get_db_adaptive())
            try:
                db.delete(entrada)
                db.commit()
                
                producto_nombre = entrada.producto.nombre if entrada.producto else "Producto"
                existente = db.query(Existencia).filter(
                    Existencia.producto_id == entrada.producto_id,
                    Existencia.almacen == entrada.almacen
                ).first()
                
                if existente:
                    if entrada.tipo == "entrada":
                        existente.cantidad = max(0, existente.cantidad - entrada.cantidad)
                    else:
                        existente.cantidad = existente.cantidad + entrada.cantidad
                    db.commit()
                
                if is_online():
                    try:
                        settings = get_settings()
                        remote_engine = create_engine(settings.DATABASE_URL)
                        
                        with remote_engine.connect() as conn:
                            conn.execute(text("DELETE FROM movimientos WHERE id = :id"), {"id": entrada.id})
                            conn.commit()
                            print("[SYNC] Entrada eliminada en Supabase por ID")
                        remote_engine.dispose()
                    except Exception as e:
                        print(f"[SYNC] Error al sincronizar eliminación: {e}")
                else:
                    queue = get_sync_queue()
                    queue.add_pending('movimientos', 'delete', {
                        'id': entrada.id,
                        'producto_id': entrada.producto_id,
                        'tipo': entrada.tipo,
                        'cantidad': entrada.cantidad,
                        'fecha_movimiento': entrada.fecha_movimiento.isoformat() if entrada.fecha_movimiento else None,
                    })
                
                self._load_entradas_pendientes()
                
                self.active_dialog.open = False
                self.page.update()
                
                snack = ft.SnackBar(
                    content=ft.Text(f"✓ Entrada de {entrada.cantidad} {producto_nombre} eliminada. Stock revertido."),
                    bgcolor=ft.Colors.GREEN_700
                )
                self.page.overlay.append(snack)
                snack.open = True
                self.page.update()
                
            except Exception as ex:
                db.rollback()
                logger.error(f"Error eliminando entrada: {ex}")
                
                snack = ft.SnackBar(
                    content=ft.Text(f"❌ Error: {str(ex)[:50]}"),
                    bgcolor=ft.Colors.RED_700
                )
                self.page.overlay.append(snack)
                snack.open = True
                self.page.update()
            finally:
                db.close()
        
        producto_nombre = entrada.producto.nombre if entrada.producto else "Producto"
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Text("Confirmar eliminación"),
            content=ft.Text(f"¿Eliminar la entrada de {entrada.cantidad} {producto_nombre}?"),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton(
                    "Eliminar",
                    bgcolor=ft.Colors.RED_600,
                    color="white",
                    on_click=on_confirmar
                )
            ]
        )
        self.page.overlay.clear()
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _show_validar_dialog(self, e):
        factura_input = ft.TextField(
            label="Número de Factura", 
            border_radius=10, 
            autofocus=True,
            hint_text="Ej: FAC-2024-001"
        )
        
        def on_confirmar(ev):
            self.active_dialog.open = False
            self.page.update()
            self._process_validation(factura_input.value)

        self.active_dialog = ft.AlertDialog(
            title=ft.Text("Validar Entradas"),
            content=ft.Column([
                ft.Text(f"Se vincularán {len(self.selected_entradas)} entradas seleccionadas."),
                factura_input
            ], tight=True, spacing=15),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton(
                    "Validar ahora", 
                    bgcolor=ft.Colors.BLUE_600, 
                    color="white", 
                    on_click=on_confirmar
                )
            ]
        )
        
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _process_validation(self, ref_factura):
        db = next(get_db_adaptive())
        try:
            nueva_fac = Factura(
                numero_factura=ref_factura if ref_factura else f"V-REF-{datetime.now().strftime('%H%M%S')}",
                proveedor="Varios",
                fecha_factura=datetime.now(),
                fecha_recepcion=datetime.now(),
                total_bruto=0, total_impuestos=0, total_neto=0,
                estado="Validada",
                validada_por="Admin",
                fecha_validacion=datetime.now()
            )
            db.add(nueva_fac)
            db.flush()

            movimientos = db.query(Movimiento).filter(Movimiento.id.in_(list(self.selected_entradas))).all()
            for m in movimientos:
                m.factura_id = nueva_fac.id
            
            db.commit()
            self.selected_entradas.clear()
            
            if is_online():
                try:
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
                        
                        result = conn.execute(text("SELECT id FROM facturas WHERE numero_factura = :num"), 
                                             {'num': nueva_fac.numero_factura})
                        supabase_factura_id = result.fetchone()[0]
                        
                        for m in movimientos:
                            conn.execute(text("""
                                UPDATE movimientos SET factura_id = :fac_id WHERE id = :mov_id
                            """), {'fac_id': supabase_factura_id, 'mov_id': m.id})
                        
                        conn.commit()
                    remote_engine.dispose()
                    print("[SYNC] Validación sincronizada a Supabase")
                except Exception as e:
                    print(f"[SYNC] Error sincronizando validación: {e}")
            
            self._load_entradas_pendientes()
            
            snack = ft.SnackBar(content=ft.Text("✅ Entradas validadas correctamente"), bgcolor=ft.Colors.GREEN_700)
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()

        except Exception as ex:
            db.rollback()
            logger.error(f"Error procesando validación: {ex}")
            snack_err = ft.SnackBar(content=ft.Text(f"❌ Error: {str(ex)[:50]}"), bgcolor=ft.Colors.RED_700)
            self.page.overlay.append(snack_err)
            snack_err.open = True
            self.page.update()
        finally:
            db.close()

    def _close_dialog(self, e=None):
        if hasattr(self, 'active_dialog') and self.active_dialog:
            self.active_dialog.open = False
            if self.page:
                self.page.update()