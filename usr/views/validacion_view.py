import flet as ft
import asyncio
import traceback
from datetime import datetime
from sqlalchemy import create_engine, text
from usr.database.base import get_db, get_db_adaptive, is_online
from usr.models import Movimiento, Factura,Producto, Categoria, Existencia
from usr.logger import get_logger
from usr.theme import get_theme, get_colors
from config.config import get_settings
from usr.notifications import show_success, show_error, show_info
from usr.whatsapp_notifier import send_whatsapp_message, format_validation_message

logger = get_logger(__name__)


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
        
        # Registrar callback para sync automático
        from usr.database.sync_callbacks import register_sync_callback
        register_sync_callback(self._on_sync_complete)
        
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
    
    def will_unmount(self):
        """Se ejecuta cuando el control se移除 de la página."""
        from usr.database.sync_callbacks import unregister_sync_callback
        unregister_sync_callback(self._on_sync_complete)
    
    def _on_sync_complete(self):
        """Callback que se ejecuta después de cada sync automático."""
        if hasattr(self, 'page') and self.page and self.visible:
            async def _reload():
                await asyncio.to_thread(self._load_entradas_pendientes)
            self.page.run_task(_reload)
    
    def on_sync_complete(self):
        """Alias para compatibilidad con SyncManager callback."""
        self._on_sync_complete()

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
                        on_click=lambda _: self._on_refresh(),
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

    def _on_refresh(self):
        """Refresca datos - hace sync solo si está online"""
        if not self.page:
            return
        
        online = is_online()
        
        if online:
            from usr.database import get_sync_manager
            sync_mgr = get_sync_manager()
            if sync_mgr:
                sync_mgr.force_sync_now()
        
        self._load_entradas_pendientes()
        
        if self.page and self.page.overlay is not None:
            self.page.overlay.clear()
        show_info("Actualizando...", duration=1)
    
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
            from usr.error_handler import show_error
            import traceback
            show_error("Error cargando entradas", ex, "validacion_view._load_entradas_pendientes")
            logger.error(f"Error cargando entradas: {ex}")
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
                
                show_success(f"Entrada de {entrada.cantidad} {producto_nombre} eliminada. Stock revertido.")
                
            except Exception as ex:
                db.rollback()
                logger.error(f"Error eliminando entrada: {ex}")
                
                show_error(f"Error: {str(ex)[:50]}")
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
        from usr.database.local_replica import LocalReplica
        
        # Obtener usuario actual
        usuario_actual = LocalReplica.get_usuario_dispositivo()
        nombre_usuario = usuario_actual['nombre'] if usuario_actual else "Sistema"
        
        # Detectar tamaño de pantalla
        is_mobile = self.page.width < 600 if self.page else False
        
        # Obtener colores del tema
        theme_colors = _colors(self.page)
        
        # ==================== VARIABLES DE ESTADO ====================
        monto_total_ves = [0]
        pagos_agregados = []  # [{"tipo": "transferencia|efectivo|divisas", "monto": float, "tasa": float|None, "ref": str}]
        faltante_ves = [0]
        panel_activo = [None]  # None | "transferencia" | "efectivo" | "divisas"
        
        # ==================== CAMPOS DEL FORMULARIO ====================
        factura_input = ft.TextField(
            label="Número de Factura", 
            border_radius=10, 
            autofocus=True,
            hint_text="Ej: FAC-2024-001",
            expand=True
        )
        
        # Proveedor - Dropdown
        proveedores = LocalReplica.get_proveedores(estado="Activo")
        proveedor_opts = [ft.dropdown.Option(p['nombre'], p['nombre']) for p in proveedores]
        proveedor_opts.append(ft.dropdown.Option("__nuevo__", "+ Agregar nuevo"))
        
        proveedor_dd = ft.Dropdown(
            label="Proveedor",
            options=proveedor_opts,
            border_radius=10,
            expand=True
        )
        
        nuevo_proveedor_input = ft.TextField(
            label="Nuevo Proveedor",
            border_radius=10,
            expand=True,
            visible=False,
            on_change=lambda e: self.page.update()
        )
        
        def on_proveedor_change(e):
            if proveedor_dd.value == "__nuevo__":
                nuevo_proveedor_input.visible = True
            else:
                nuevo_proveedor_input.visible = False
            self.page.update()
        proveedor_dd.on_change = on_proveedor_change
        
        # ==================== ESTILO DE SECCIONES ====================
        
        def section_container(content_col):
            return ft.Container(
                content=content_col,
                padding=15,
                border_radius=12,
                border=ft.border.all(1, theme_colors.get('border', '#333333')),
                bgcolor=theme_colors.get('surface', '#252525')
            )
        
        # ==================== MONTO TOTAL ====================
        
        monto_total_input = ft.TextField(
            label="💰 Monto Total (VES)",
            prefix_icon=ft.Icons.ATTACH_MONEY,
            border_radius=10,
            hint_text="1000.00",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True,
            text_style=ft.TextStyle(size=16, weight=ft.FontWeight.BOLD)
        )
        
        # ==================== TRANSFERENCIA ====================
        
        transferencia_monto_input = ft.TextField(
            label="🏦 Transferencia (VES)",
            prefix_icon=ft.Icons.ACCOUNT_BALANCE,
            border_radius=10,
            hint_text="0.00",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True
        )
        
        transferencia_ref_input = ft.TextField(
            label="Referencia",
            prefix_icon=ft.Icons.LABEL,
            border_radius=10,
            hint_text="Nro. operación...",
            expand=True
        )
        
        # ==================== EFECTIVO BS ====================
        
        efectivo_bs_monto_input = ft.TextField(
            label="💵 Efectivo Bs (VES)",
            prefix_icon=ft.Icons.PAYMENTS,
            border_radius=10,
            hint_text="0.00",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True
        )
        
        # ==================== DIVISAS ====================
        
        divisas_tasa_input = ft.TextField(
            label="Tasa (VES/USD)",
            prefix_icon=ft.Icons.CURRENCY_EXCHANGE,
            border_radius=10,
            hint_text="1",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True
        )
        
        divisas_monto_usd_input = ft.TextField(
            label="Monto en USD",
            prefix_icon=ft.Icons.CURRENCY_EXCHANGE,
            border_radius=10,
            hint_text="0.00",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True
        )
        
        # ==================== LISTA DE PAGOS ====================
        
        pagos_list_view = ft.ListView(spacing=5, padding=10)
        
        def actualizar_pagos_lista():
            """Actualiza la lista de pagos agregados"""
            pagos_list_view.controls.clear()
            for i, pago in enumerate(pagos_agregados):
                if pago["tipo"] == "transferencia":
                    texto = f"🏦 Transferencia {pago['monto']:,.0f} VES"
                    if pago.get("ref"):
                        texto += f" (Ref: {pago['ref']})"
                elif pago["tipo"] == "efectivo":
                    texto = f"💵 Efectivo {pago['monto']:,.0f} VES"
                else:  # divisas
                    texto = f"💱 Divisas {pago['monto']:,.2f} USD @ {pago['tasa']:.2f}"
                
                pago_item = ft.Container(
                    content=ft.Row([
                        ft.Text(texto, size=13, expand=True),
                        ft.IconButton(
                            icon=ft.Icons.DELETE_OUTLINE,
                            icon_color=theme_colors.get('error'),
                            on_click=lambda _, idx=i: eliminar_pago(idx)
                        )
                    ]),
                    bgcolor=theme_colors.get('surface'),
                    border_radius=8,
                    padding=10
                )
                pagos_list_view.controls.append(pago_item)
            self.page.update()
        
        def eliminar_pago(index):
            """Elimina un pago de la lista"""
            pago = pagos_agregados.pop(index)
            # Reintegrar al faltante
            monto_ves = pago["monto"] * pago.get("tasa", 1)
            faltante_ves[0] += monto_ves
            actualizar_pagos_lista()
            actualizar_resumen()
        
        # ==================== RESUMEN ====================
        
        faltante_icon = ft.Icon(ft.Icons.HOURGLASS_EMPTY, size=24)
        faltante_text = ft.Text(
            "Faltante: 0 VES",
            size=14,
            weight=ft.FontWeight.BOLD,
            color=theme_colors.get('warning', '#FF9800')
        )
        
        def update_resumen_colors(faltante):
            """Actualiza colores del resumen según el estado"""
            if abs(faltante) < 0.01:
                summary_bg = ft.Colors.with_opacity(0.1, ft.Colors.GREEN)
                summary_border = ft.Colors.GREEN_400
                faltante_icon.name = ft.Icons.CHECK_CIRCLE
                faltante_icon.color = ft.Colors.GREEN_400
                text = "✅ PAGO COMPLETO"
            elif faltante > 0:
                summary_bg = ft.Colors.with_opacity(0.1, ft.Colors.ORANGE)
                summary_border = ft.Colors.ORANGE_400
                faltante_icon.name = ft.Icons.WARNING_AMBER_ROUNDED
                faltante_icon.color = ft.Colors.ORANGE_400
                text = f"⚠️ FALTANTE: {faltante:,.2f} VES"
            else:
                summary_bg = ft.Colors.with_opacity(0.1, ft.Colors.RED)
                summary_border = ft.Colors.RED_400
                faltante_icon.name = ft.Icons.ERROR_OUTLINE
                faltante_icon.color = ft.Colors.RED_400
                text = f"❌ EXCEDENTE: {abs(faltante):,.2f} VES"
            
            faltante_text.value = text
            return text
        
        resumen_container = ft.Container(
            content=ft.Row([faltante_icon, faltante_text], spacing=8),
            padding=15,
            border_radius=10,
            border=ft.border.all(2, theme_colors.get('border', '#333333'))
        )
        
        # ==================== FECHA ====================
        
        fecha_picker = ft.DatePicker(
            first_date=datetime(2020, 1, 1),
            last_date=datetime.now(),
            value=datetime.now()
        )
        
        fecha_label = ft.Text(
            f"Fecha: {datetime.now().strftime('%d/%m/%Y')}",
            size=12,
            color=theme_colors.get('text_secondary')
        )
        
        fecha_btn = ft.ElevatedButton(
            "📅 Fecha",
            on_click=lambda _: self.page.open(fecha_picker)
        )
        
        def on_fecha_change(e):
            fecha_label.value = f"Fecha: {fecha_picker.value.strftime('%d/%m/%Y')}"
            self.page.update()
        
        fecha_picker.on_change = on_fecha_change
        
# ==================== FUNCIONES DE CÁLCULO ====================
        
        def actualizar_resumen():
            """Actualiza el resumen de pagos y el faltante"""
            update_resumen_colors(faltante_ves[0])
            validar_btn.disabled = faltante_ves[0] > 0.01
            self.page.update()
        
        def on_monto_total_change(e):
            """Cuando cambia el monto total"""
            try:
                monto_total_ves[0] = float(monto_total_input.value) if monto_total_input.value else 0
            except:
                monto_total_ves[0] = 0
            
            faltante_ves[0] = monto_total_ves[0]
            actualizar_resumen()
        
        # Asignar eventos on_change
        monto_total_input.on_change = on_monto_total_change
        
        # ==================== PANEL DE CONTROLES ====================
        
        controls_container = ft.Container(visible=False)
        
        def abrir_panel(metodo):
            """Abre el panel decontrols para el método seleccionado"""
            panel_activo[0] = metodo
            
            # Pre-cargar campos
            if metodo == "divisas":
                # Tasa por defecto 1, monto equivalente
                tasas = 1
                usd_calc = faltante_ves[0] / tasas if tasas > 0 else 0
                divisas_tasa_input.value = "1"
                divisas_monto_usd_input.value = f"{usd_calc:.2f}"
                
                # Asignar event handler para recálculo automático
                def recalcular_divisas(e):
                    try:
                        tasa_val = float(divisas_tasa_input.value or "1")
                        if tasa_val <= 0:
                            tasa_val = 1
                    except:
                        tasa_val = 1
                    monto_usd = faltante_ves[0] / tasa_val if tasa_val > 0 else 0
                    divisas_monto_usd_input.value = f"{monto_usd:.2f}"
                    self.page.update()
                
                divisas_tasa_input.on_change = recalcular_divisas
            else:
                # Transferencia/Efectivo: precargar faltante
                if metodo == "transferencia":
                    transferencia_monto_input.value = f"{faltante_ves[0]:.2f}"
                else:
                    efectivo_bs_monto_input.value = f"{faltante_ves[0]:.2f}"
            
            # Mostrar controls
            controles = []
            if metodo == "transferencia":
                controles = [transferencia_monto_input, transferencia_ref_input]
            elif metodo == "efectivo":
                controles = [efectivo_bs_monto_input]
            else:  # divisas
                controles = [divisas_tasa_input, divisas_monto_usd_input]
            
            controls_container.content = ft.Column(
                controles + [ft.ElevatedButton("➕ Agregar", on_click=lambda _: agregar_pago(metodo))],
                spacing=10
            )
            controls_container.visible = True
            self.page.update()
        
        def agregar_pago(metodo):
            """Agrega un pago a la lista"""
            if metodo == "transferencia":
                try:
                    monto = float(transferencia_monto_input.value or "0")
                except:
                    monto = 0
                ref = transferencia_ref_input.value or ""
                if monto > 0:
                    pagos_agregados.append({
                        "tipo": "transferencia",
                        "monto": monto,
                        "tasa": 1,
                        "ref": ref
                    })
                    faltante_ves[0] -= monto
                    transferencia_monto_input.value = ""
                    transferencia_ref_input.value = ""
            
            elif metodo == "efectivo":
                try:
                    monto = float(efectivo_bs_monto_input.value or "0")
                except:
                    monto = 0
                if monto > 0:
                    pagos_agregados.append({
                        "tipo": "efectivo",
                        "monto": monto,
                        "tasa": 1,
                        "ref": ""
                    })
                    faltante_ves[0] -= monto
                    efectivo_bs_monto_input.value = ""
            
            else:  # divisas
                try:
                    tasas = float(divisas_tasa_input.value or "1")
                    if tasas <= 0:
                        tasas = 1
                except:
                    tasas = 1
                try:
                    monto_usd = float(divisas_monto_usd_input.value or "0")
                except:
                    monto_usd = 0
                monto_ves = monto_usd * tasas
                if monto_ves > 0:
                    pagos_agregados.append({
                        "tipo": "divisas",
                        "monto": monto_usd,
                        "tasa": tasas,
                        "ref": ""
                    })
                    faltante_ves[0] -= monto_ves
                    divisas_monto_usd_input.value = ""
            
            # Cerrar panel
            controls_container.visible = False
            panel_activo[0] = None
            
            # Actualizar UI
            actualizar_pagos_lista()
            actualizar_resumen()
        
        # ==================== BOTONES ====================
        
        validar_btn = ft.ElevatedButton(
            "✓ Validar Entradas",
            bgcolor=theme_colors.get('success', '#4CAF50'),
            color="white",
            disabled=True,
            height=45
        )
        
        def on_confirmar(ev):
            # Validar monto total
            try:
                monto = float(monto_total_input.value) if monto_total_input.value else 0
            except:
                monto = 0
            
            # Obtener fecha
            fecha_fac = fecha_picker.value if fecha_picker.value else datetime.now()
            
            # Determinar proveedor
            if proveedor_dd.value == "__nuevo__":
                prov_seleccionado = nuevo_proveedor_input.value if nuevo_proveedor_input.value else "Varios"
            elif proveedor_dd.value:
                prov_seleccionado = proveedor_dd.value
            else:
                prov_seleccionado = "Varios"
            
            # Preparar datos de pagos desde la lista
            pagos_data = {'pagos': pagos_agregados}
            
            self.active_dialog.open = False
            self.page.update()
            
            # Llamar al proceso de validación
            self._process_validation(
                ref_factura=factura_input.value,
                proveedor=prov_seleccionado,
                monto=monto,
                fecha_factura=fecha_fac,
                usuario=nombre_usuario,
                pagos=pagos_data
            )
        
        validar_btn.on_click = on_confirmar
        
        # ==================== CONSTRUIR DIÁLOGO ====================
        
        # Aumentar ancho para PC
        dialog_width = 400 if is_mobile else 650
        
        usuario_label = ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.PERSON, size=18, color=theme_colors.get('accent', '#BB86FC')),
                ft.Text(f"Validado por: {nombre_usuario}", weight="bold", size=13, color=theme_colors.get('text_primary', '#FFFFFF'))
            ]),
            padding=ft.padding.symmetric(horizontal=12, vertical=8),
            bgcolor=theme_colors.get('accent_dark', '#9A67EA'),
            border_radius=8
        )
        
        # Sección: Datos del Documento
        doc_section = section_container(ft.Column([
            ft.Row([ft.Icon(ft.Icons.RECEIPT_LONG), ft.Text("📋 Datos del Documento", weight="bold", size=14)]),
            ft.Row([factura_input], spacing=10),
            ft.Row([proveedor_dd]),
            ft.Row([nuevo_proveedor_input]),
            ft.Row([fecha_btn, fecha_label], spacing=10),
        ], spacing=10))
        
        # Sección: Montos
        monto_section = section_container(ft.Column([
            ft.Row([ft.Icon(ft.Icons.ATTACH_MONEY), ft.Text("💰 Monto Total", weight="bold", size=14)]),
            monto_total_input,
        ], spacing=10))
        
        # ==================== BOTONES DE MÉTODOS ====================
        
        btn_transfer = ft.ElevatedButton(
            "🏦 Transferencia",
            on_click=lambda _: abrir_panel("transferencia")
        )
        btn_efectivo = ft.ElevatedButton(
            "💵 Efectivo",
            on_click=lambda _: abrir_panel("efectivo")
        )
        btn_divisas = ft.ElevatedButton(
            "💱 Divisas",
            on_click=lambda _: abrir_panel("divisas")
        )
        
        metodos_row = ft.Row(
            [btn_transfer, btn_efectivo, btn_divisas],
            spacing=10
        )
        
        # ==================== SECCIÓN DE PAGOS ====================
        
        pagos_section = section_container(ft.Column([
            ft.Row([ft.Icon(ft.Icons.PAYMENTS), ft.Text("💳 Distribución de Pago", weight="bold", size=14)]),
            ft.Container(height=5),
            metodos_row,
            ft.Divider(height=10),
            controls_container,
            ft.Container(
                content=ft.Column([
                    ft.Text("Pagos agregados:", weight="bold", size=12),
                    pagos_list_view
                ], spacing=5),
                padding=10,
                bgcolor=theme_colors.get('surface'),
                border_radius=8
            ),
        ], spacing=5))
        
        content = ft.Column([
            usuario_label,
            ft.Divider(height=1),
            ft.Text(f"Se validarán {len(self.selected_entradas)} entrada(s)", weight="bold", size=14),
            ft.Container(height=5),
            doc_section,
            ft.Container(height=10),
            monto_section,
            ft.Container(height=10),
            pagos_section,
            ft.Container(height=10),
            resumen_container,
            ft.Container(height=5),
            validar_btn,
        ], spacing=0, scroll=ft.ScrollMode.AUTO)
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Text("✅ Validar Entradas"),
            content=ft.Container(
                width=dialog_width,
                content=content,
                padding=20
            ),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
            ],
            actions_alignment=ft.MainAxisAlignment.END
        )
        
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()
    
    def _on_proveedor_change(self, e):
        """Maneja el cambio en el dropdown de proveedor"""
        pass
    
    def _process_validation(self, ref_factura, proveedor="Varios", monto=0, fecha_factura=None, usuario="Sistema", pagos=None):
        db = next(get_db_adaptive())
        pagos = pagos or {}
        
        # Asegurar que la columna tasa_cambio exista
        try:
            from sqlalchemy import text
            db.execute(text("ALTER TABLE factura_pagos ADD COLUMN tasa_cambio REAL"))
            db.commit()
        except:
            pass
        
        if fecha_factura is None:
            fecha_factura = datetime.now()
        
        try:
            # 1. Crear factura local con los nuevos campos
            nueva_fac = Factura(
                numero_factura=ref_factura if ref_factura else f"V-REF-{datetime.now().strftime('%H%M%S')}",
                proveedor=proveedor,
                fecha_factura=fecha_factura,
                fecha_recepcion=datetime.now(),
                total_bruto=monto,
                total_impuestos=0,
                total_neto=monto,
                estado="Validada",
                validada_por=usuario,
                fecha_validacion=datetime.now()
            )
            db.add(nueva_fac)
            db.flush()
            
            # 2. Guardar pagos de factura (nuevo formato)
            from usr.models import FacturaPago
            
            # Soporta formato nuevo ['pagos'] o formato antiguo dict
            lista_pagos = []
            if isinstance(pagos, dict) and 'pagos' in pagos:
                lista_pagos = pagos['pagos']
            
            for pago in lista_pagos:
                tipo = pago.get('tipo', '')
                monto_pago = pago.get('monto', 0)
                tasa = pago.get('tasa', 1)
                ref = pago.get('ref', '')
                
                # Calcular monto en VES
                monto_ves = monto_pago * tasa
                
                nuevo_pago = FacturaPago(
                    factura_id=nueva_fac.id,
                    tipo_pago=tipo,
                    monto=monto_ves,
                    referencia=ref,
                    tasa_cambio=tasa if tipo == 'divisas' else None
                )
                db.add(nuevo_pago)
            
            # 3. Actualizar movimientos locales
            movimientos = db.query(Movimiento).filter(Movimiento.id.in_(list(self.selected_entradas))).all()
            for m in movimientos:
                m.factura_id = nueva_fac.id
            
            db.commit()
            self.selected_entradas.clear()
            
            # 4. Sincronizar con Supabase si está online
            if is_online():
                try:
                    settings = get_settings()
                    remote_engine = create_engine(settings.DATABASE_URL)
                    
                    with remote_engine.connect() as conn:
                        # Insertar factura en Supabase
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
                        
                        # Obtener ID de factura en Supabase
                        result = conn.execute(text("SELECT id FROM facturas WHERE numero_factura = :num"), 
                                            {'num': nueva_fac.numero_factura})
                        supabase_fac_id = result.fetchone()[0]
                        
                        # Actualizar movimientos en Supabase
                        for m in movimientos:
                            conn.execute(text("UPDATE movimientos SET factura_id = :fac_id WHERE id = :mov_id"),
                                       {'fac_id': supabase_fac_id, 'mov_id': m.id})
                        
                        # Insertar pagos en Supabase (nuevo formato)
                        lista_pagos_sync = pagos.get('pagos', []) if isinstance(pagos, dict) else []
                        
                        for pago in lista_pagos_sync:
                            tipo = pago.get('tipo', '')
                            monto_pago = pago.get('monto', 0)
                            tasa = pago.get('tasa', 1)
                            ref = pago.get('ref', '')
                            monto_ves = monto_pago * tasa
                            
                            conn.execute(text("""
                                INSERT INTO factura_pagos (factura_id, tipo_pago, monto, referencia, tasa_cambio)
                                VALUES (:factura_id, :tipo, :monto, :ref, :tasa)
                            """), {
                                'factura_id': supabase_fac_id,
                                'tipo': tipo,
                                'monto': monto_ves,
                                'ref': ref,
                                'tasa': tasa if tipo == 'divisas' else None
                            })
                        
                        conn.commit()
                        print("[SYNC] Validación sincronizada a Supabase")
                except Exception as e:
                    print(f"[SYNC] Error sincronizando validación: {e}")
            
            # 4. Recargar vista
            self._load_entradas_pendientes()
            show_success("Entradas validadas correctamente")
            
            # 5. Enviar notificación a WhatsApp
            try:
                # Obtener datos para el mensaje
                factura_num = nueva_fac.numero_factura
                productos_info = []
                for m in movimientos:
                    prod = db.query(Producto).filter(Producto.id == m.producto_id).first()
                    if prod:
                        productos_info.append(f"{m.cantidad} x {prod.nombre}")
                
                msg = format_validation_message(
                    ", ".join(productos_info[:3]) + ("..." if len(productos_info) > 3 else ""),
                    sum(m.cantidad for m in movimientos),
                    factura_num,
                    nueva_fac.proveedor,
                    monto if monto else nueva_fac.total_neto,
                    pagos,
                    nueva_fac.validada_por
                )
                send_whatsapp_message(msg)
            except Exception as e:
                print(f"[WHATSAPP] Error enviando notificación: {e}")
                
        except Exception as ex:
            db.rollback()
            logger.error(f"Error procesando validación: {ex}")
            show_error(f"Error: {str(ex)[:50]}")
        finally:
            db.close()
    
    def _clear_selection(self, e=None):
        """Limpia la selección de entradas."""
        self.selected_entradas.clear()
        
        # Actualizar botones
        self.validate_button.disabled = True
        self.validate_button.text = "Validar entradas"
        
        self.clear_button.disabled = True
        
        # Recargar la vista para actualizar la UI
        self._load_entradas_pendientes()
        
        if self.page:
            self.page.update()
    
    def _close_dialog(self, e=None):
        if hasattr(self, 'active_dialog') and self.active_dialog:
            self.active_dialog.open = False
            if self.page:
                self.page.update()