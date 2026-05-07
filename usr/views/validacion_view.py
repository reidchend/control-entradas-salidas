import flet as ft
import asyncio
from usr.database.base import get_db_adaptive, is_online
from usr.models import Movimiento
from usr.logger import get_logger
from usr.theme import get_colors
from usr.notifications import show_success, show_error
from usr.views.validacion import ValidacionDialog
from usr.database.sync_callbacks import register_sync_callback, unregister_sync_callback

logger = get_logger(__name__)


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
        self.cards_dict = {}
        self._connection_indicator = None
        self._connection_thread = None

    def build(self):
        self._build_controls()
        register_sync_callback(self._on_sync_complete)

    def did_mount(self):
        self._build_controls()
        if self.page and self.page.client_storage:
            self._load_entradas_pendientes()
            if self.page:
                self.update()
        
        self._update_connection_indicator()
        self._start_connection_monitor()

    def will_unmount(self):
        unregister_sync_callback(self._on_sync_complete)

    def _on_sync_complete(self):
        if hasattr(self, 'page') and self.page and self.visible:
            self._load_entradas_pendientes()

    def _update_connection_indicator(self):
        if not hasattr(self, '_connection_indicator') or not self._connection_indicator:
            return
        try:
            online = is_online()
            self._connection_indicator.content = ft.Icon(
                ft.Icons.WIFI if online else ft.Icons.WIFI_OFF,
                color=ft.Colors.GREEN_400 if online else ft.Colors.RED_400,
                size=18
            )
            self._connection_indicator.tooltip = "Conectado" if online else "Sin conexión"
            if self.page and self._connection_indicator.page:
                self._connection_indicator.update()
        except:
            pass

    def _start_connection_monitor(self):
        import threading, time
        def loop():
            while True:
                time.sleep(10)
                if hasattr(self, 'page') and self.page:
                    self._update_connection_indicator()
                    try:
                        self.page.update()
                    except:
                        pass
        self._connection_thread = threading.Thread(target=loop, daemon=True)
        self._connection_thread.start()

    def _build_controls(self):
        colors = get_colors(self.page)
        
        # Connection indicator
        self._connection_indicator = ft.Container(
            content=ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18),
            tooltip="Conectado",
            padding=5,
            on_click=self._on_sync_indicator_click
        )
        
        self.search_field = ft.TextField(
            hint_text="Buscar...",
            prefix_icon=ft.Icons.SEARCH_ROUNDED,
            border_radius=12,
            border_color=colors.get('input_border'),
            focused_border_color=colors.get('accent'),
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
        
        controls = ft.Container(
            content=ft.Column([
                self.search_field,
                ft.Row([self.validate_button, self.clear_button], alignment=ft.MainAxisAlignment.SPACE_BETWEEN)
            ], spacing=10),
            padding=ft.padding.symmetric(horizontal=20, vertical=10),
        )
        
        self.content = ft.Column([header, controls, self.entradas_list], spacing=0, expand=True)

    def _on_sync_indicator_click(self, e=None):
        from usr.database import get_sync_manager
        sync_mgr = get_sync_manager()
        if not sync_mgr or not self.page:
            return
        self._update_connection_indicator()
        if self.page:
            self.page.update()

    def _on_refresh(self):
        if not self.page:
            return
        online = is_online()
        if online:
            from usr.database import get_sync_manager
            sync_mgr = get_sync_manager()
            if sync_mgr:
                sync_mgr.force_sync_now()
        self._load_entradas_pendientes()

    def _show_validar_dialog(self, e):
        theme_colors = get_colors(self.page)
        dialog = ValidacionDialog(self.page, self.selected_entradas, theme_colors)
        
        def on_validar_click(btn_event):
            data = dialog.get_data()
            dialog.dialog.open = False
            self.page.update()
            
            from usr.views.validacion.service import ValidacionService
            try:
                result = ValidacionService.procesar(data, self.selected_entradas)
                show_success(f"✅ Validadas {result.get('movimientos_count', 0)} entradas")
                if result.get('sync'):
                    print("[SYNC] Factura sincronizada")
                self.selected_entradas.clear()
                self._load_entradas_pendientes()
            except Exception as ex:
                show_error(f"Error: {str(ex)}")
        
        dialog.set_on_validate(on_validar_click)
        dialog.show()

    def _load_entradas_pendientes(self):
        if self.is_loading:
            return
        self.is_loading = True
        
        self.entradas_list.controls = [ft.ProgressBar()]
        
        db = None
        try:
            db = next(get_db_adaptive())
            query = db.query(Movimiento).filter(
                Movimiento.tipo == "entrada",
                Movimiento.factura_id.is_(None)
            )
            
            search = self.search_field.value.lower().strip() if self.search_field.value else ""
            if search:
                from usr.models import Producto
                query = query.join(Producto).filter(Producto.nombre.ilike(f"%{search}%"))
            
            entradas = query.order_by(Movimiento.fecha_movimiento.desc()).all()
            self.entradas_data = {e.id: e for e in entradas}
            
            self.entradas_list.controls.clear()
            if not entradas:
                self.entradas_list.controls.append(ft.Container(
                    content=ft.Column([
                        ft.Icon(ft.Icons.FACT_CHECK_OUTLINED, size=50, color=ft.Colors.GREY_300),
                        ft.Text("Sin entradas pendientes", color=ft.Colors.GREY_400)
                    ], horizontal_alignment="center"),
                    padding=ft.padding.only(top=100),
                    alignment="center"
                ))
            else:
                for ent in entradas:
                    self.entradas_list.controls.append(self._create_entrada_card(ent))
            
            self._update_buttons()
            if self.page:
                self.update()
        except Exception as ex:
            logger.error(f"Error cargando entradas: {ex}")
            self.entradas_list.controls = [ft.Text(f"Error: {str(ex)}")]
        finally:
            if db: db.close()
            self.is_loading = False

    def _create_entrada_card(self, entrada):
        colors = get_colors(self.page)
        is_selected = entrada.id in self.selected_entradas
        
        # Get producto safely
        try:
            producto = entrada.producto
            nombre = getattr(producto, 'nombre', 'Sin nombre') if producto else "Sin nombre"
            unidad = getattr(producto, 'unidad_medida', 'uds') if producto else 'uds'
            es_pesable = getattr(producto, 'es_pesable', False) if producto else False
        except:
            nombre = "Sin nombre"
            unidad = 'uds'
            es_pesable = False
        
        almacen = getattr(entrada, 'almacen', 'principal') or 'principal'
        peso = getattr(entrada, 'peso_total', 0) or 0
        
        almacen_badge = ft.Text(
            f"📦 {almacen.title()}",
            size=10,
            color=colors['text_secondary'],
        )
        
        if es_pesable and peso > 0:
            cantidad_texto = f"{peso:.3f} kg"
        else:
            cantidad_texto = f"{entrada.cantidad} {unidad}"
        
        if peso > 0.001:
            peso_badge = ft.Text(f"⚖️ {peso:.3f} kg", size=10, color='#FF9800')
        else:
            peso_badge = ft.Text()
        
        check_icon = ft.Icon(
            ft.Icons.CHECK_CIRCLE_ROUNDED if is_selected else ft.Icons.RADIO_BUTTON_UNCHECKED_ROUNDED,
            color=colors['accent'] if is_selected else colors['text_hint'],
            size=22
        )
        
        card = ft.Container(
            content=ft.Row([
                ft.Container(content=check_icon, padding=2),
                ft.Column([
                    ft.Text(
                        nombre,
                        weight=ft.FontWeight.BOLD,
                        size=15,
                        color=colors['text_primary'],
                        max_lines=1,
                        overflow=ft.TextOverflow.ELLIPSIS
                    ),
                    ft.Row([
                        ft.Text(cantidad_texto, size=13, weight="w600", color=colors['success']),
                        peso_badge,
                        ft.Container(expand=True),
                        ft.Text(
                            entrada.fecha_movimiento.strftime("%d/%m %H:%M") if entrada.fecha_movimiento else "Sin fecha",
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
                    on_click=lambda _: self._eliminar_entrada(entrada)
                )
            ], spacing=8),
            padding=15,
            animate=200,
            bgcolor=colors['card_hover'] if is_selected else colors['card'],
            border_radius=12,
            border=ft.border.all(2, colors['accent']) if is_selected else ft.border.all(1, colors['border']),
            on_click=lambda _: self._toggle_selection(entrada.id)
        )
        
        self.cards_dict[entrada.id] = card
        return card

    def _toggle_selection(self, entrada_id):
        if entrada_id in self.selected_entradas:
            self.selected_entradas.discard(entrada_id)
        else:
            self.selected_entradas.add(entrada_id)
        
        if entrada_id in self.cards_dict:
            card = self.cards_dict[entrada_id]
            is_sel = entrada_id in self.selected_entradas
            colors = get_colors(self.page)
            card.bgcolor = colors['card_hover'] if is_sel else colors['card']
            card.border = ft.border.all(2, colors['accent']) if is_sel else ft.border.all(1, colors['border'])
            if card.page:
                card.update()
        
        self._update_buttons()
        
        # Update check icon
        if entrada_id in self.cards_dict:
            card = self.cards_dict[entrada_id]
            is_sel = entrada_id in self.selected_entradas
            row = card.content
            if row and row.controls:
                check_icon = row.controls[0].content
                if isinstance(check_icon, ft.Icon):
                    check_icon.name = ft.Icons.CHECK_CIRCLE_ROUNDED if is_sel else ft.Icons.RADIO_BUTTON_UNCHECKED_ROUNDED
                    check_icon.color = get_colors(self.page)['accent'] if is_sel else get_colors(self.page)['text_hint']
                if card.page:
                    card.update()

    def _update_buttons(self):
        has_sel = len(self.selected_entradas) > 0
        self.validate_button.disabled = not has_sel
        self.clear_button.disabled = not has_sel
        if has_sel:
            self.validate_button.text = f"Validar {len(self.selected_entradas)} entradas"
        else:
            self.validate_button.text = "Validar seleccionadas"
        
        if self.page and self.validate_button.page:
            self.validate_button.update()
            self.clear_button.update()
            self.page.update()

    def _clear_selection(self, e=None):
        self.selected_entradas.clear()
        for card in self.cards_dict.values():
            if card.page:
                card.bgcolor = get_colors(self.page)['card']
                card.border = ft.border.all(1, get_colors(self.page)['border'])
                card.update()
        self._load_entradas_pendientes()

    def _eliminar_entrada(self, entrada):
        db = next(get_db_adaptive())
        try:
            db.delete(entrada)
            db.commit()
            show_success(f"Eliminado: {entrada.cantidad}")
            self._load_entradas_pendientes()
        except Exception as ex:
            db.rollback()
            show_error(f"Error: {str(ex)}")
        finally:
            db.close()