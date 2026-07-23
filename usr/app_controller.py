import flet as ft
from usr.logger import get_logger
from usr.error_handler import show_error

logger = get_logger(__name__)


class ControlEntradasSalidasApp:
    def __init__(self):
        self.page: ft.Page = None
        self.navigation_rail = None
        self.navigation_bar = None
        self.content_area = None
        self.current_view = None
        self.current_view_index = 0
        self.views = []
        self._layout_row = None
        self.settings = None
        self._switching_view = False

    async def arrancar_interfaz(self, page: ft.Page, settings, vistas_cargadas):
        self.page = page
        self.settings = settings
        try:
            from usr.database.base import init_local_tables
            init_local_tables()

            from usr.views import InventarioView, ValidacionView, StockView, ProduccionesView, ConfiguracionView, HistorialFacturasView, RequisicionesView, BandejaWhatsAppView
            v_inv = InventarioView()
            v_val = ValidacionView()
            v_sto = StockView()
            v_pro = ProduccionesView()
            v_req = RequisicionesView()
            v_his = HistorialFacturasView()
            v_cfg = ConfiguracionView()
            v_ban = BandejaWhatsAppView()
            v_req.inventario_view = v_inv
            v_req.app_controller = self

            self.views = [
                v_inv,    # 0
                v_val,    # 1
                v_sto,    # 2
                v_pro,    # 3
                v_req,    # 4
                v_his,    # 5
                v_cfg,    # 6
                v_ban,    # 7
            ]

            self.page.title = self.settings.FLET_APP_NAME
            self.page.theme_mode = ft.ThemeMode.DARK
            self.page.padding = 0
            self.page.spacing = 0
            self.page.expand = True

            self._setup_theme()
            self._create_layout()
            self._handle_responsive_layout(self.page.width)
            self._register_sync_callback()
            self._show_view(0)

            self.page.on_resized = self._on_page_resized
            self.page.update()
        except Exception as e:
            logger.error(f"Error crítico en arrancar_interfaz: {e}", exc_info=True)
            show_error("Error al iniciar la interfaz", e, "ControlEntradasSalidasApp.arrancar_interfaz")

    def _setup_theme(self):
        if not self.page:
            return
        self.page.theme = ft.Theme(color_scheme_seed=ft.Colors.DEEP_PURPLE_700, visual_density=ft.VisualDensity.COMFORTABLE, use_material3=True)
        self.page.bgcolor = '#1A1A1A'

    def _toggle_theme(self, e=None):
        if not self.page:
            return
        try:
            is_dark = self.page.theme_mode != ft.ThemeMode.DARK
            self.page.theme_mode = ft.ThemeMode.DARK if is_dark else ft.ThemeMode.LIGHT
            self.page.bgcolor = '#1A1A1A' if is_dark else '#F5F5F5'

            if hasattr(self, 'content_area') and self.content_area:
                self.content_area.bgcolor = '#252525' if is_dark else '#FFFFFF'

            if hasattr(self, 'navigation_rail') and self.navigation_rail:
                self.navigation_rail.bgcolor = '#1E1E1E' if is_dark else '#F3E5F5'

            if hasattr(self, 'theme_toggle') and self.theme_toggle:
                self.theme_toggle.icon = ft.Icons.LIGHT_MODE if is_dark else ft.Icons.DARK_MODE
                self.theme_toggle.icon_color = ft.Colors.AMBER if is_dark else ft.Colors.BLUE_GREY_700
                self.theme_toggle.tooltip = "Modo Claro" if is_dark else "Modo Oscuro"

            if self.current_view and hasattr(self.current_view, 'on_theme_change'):
                self.current_view.on_theme_change()

            self.page.update()
        except Exception as e:
            logger.error(f"Error en _toggle_theme: {e}", exc_info=True)
            show_error("Error al cambiar el tema", e, "ControlEntradasSalidasApp._toggle_theme")

    def _create_layout(self):
        try:
            self.content_area = ft.Container(expand=True, padding=0, bgcolor='#252525', border_radius=0)

            self.theme_toggle = ft.IconButton(icon=ft.Icons.LIGHT_MODE, tooltip="Modo Claro", on_click=self._toggle_theme, icon_color=ft.Colors.AMBER)

            self.navigation_rail = ft.NavigationRail(
                selected_index=0, extended=False, label_type=ft.NavigationRailLabelType.ALL, min_width=100, bgcolor='#1E1E1E',
                leading=self.theme_toggle,
                destinations=[
                    ft.NavigationRailDestination(icon=ft.Icons.SHOPPING_CART_OUTLINED, selected_icon=ft.Icons.SHOPPING_CART, label="Inventario"),
                    ft.NavigationRailDestination(icon=ft.Icons.CHECKLIST_OUTLINED, selected_icon=ft.Icons.CHECKLIST, label="Validación"),
                    ft.NavigationRailDestination(icon=ft.Icons.WAREHOUSE_OUTLINED, selected_icon=ft.Icons.WAREHOUSE, label="Stock"),
                    ft.NavigationRailDestination(icon=ft.Icons.FACTORY_OUTLINED, selected_icon=ft.Icons.FACTORY, label="Producciones"),
                    ft.NavigationRailDestination(icon=ft.Icons.LOCAL_SHIPPING_OUTLINED, selected_icon=ft.Icons.LOCAL_SHIPPING, label="Requisiciones"),
                    ft.NavigationRailDestination(icon=ft.Icons.HISTORY_OUTLINED, selected_icon=ft.Icons.HISTORY, label="Historial"),
                    ft.NavigationRailDestination(icon=ft.Icons.SETTINGS_OUTLINED, selected_icon=ft.Icons.SETTINGS, label="Ajustes"),
                    ft.NavigationRailDestination(icon=ft.Icons.MAIL_OUTLINED, selected_icon=ft.Icons.MAIL, label="Bandeja"),
                ], on_change=self._on_navigation_change,
            )

            self.navigation_bar = ft.NavigationBar(
                visible=False, bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
                destinations=[
                    ft.NavigationBarDestination(icon=ft.Icons.SHOPPING_CART_OUTLINED, label="Inventario"),
                    ft.NavigationBarDestination(icon=ft.Icons.CHECKLIST_OUTLINED, label="Validar"),
                    ft.NavigationBarDestination(icon=ft.Icons.WAREHOUSE_OUTLINED, label="Stock"),
                    ft.NavigationBarDestination(icon=ft.Icons.MORE_VERT, label="Más"),
                ], on_change=self._on_navigation_change,
            )

            self.sync_status_bar = ft.Container(
                height=0, visible=True,
                bgcolor='#2D2D2D',
                padding=ft.padding.symmetric(horizontal=12, vertical=0),
                border_radius=ft.border_radius.all(8),
                content=ft.Row([
                    ft.ProgressRing(width=14, height=14, stroke_width=2, color='#BB86FC'),
                    ft.Text("", size=12, color='#BBBBBB', expand=True, no_wrap=False),
                ], spacing=8, alignment=ft.MainAxisAlignment.START),
            )

            self._layout_row = ft.SafeArea(content=ft.Row([self.navigation_rail, self.content_area], expand=True, spacing=0), expand=True)
            self.page.clean()
            self.page.padding = 5
            self._sync_safe = ft.SafeArea(
                content=self.sync_status_bar,
                top=True, bottom=False, left=True, right=True,
            )
            self.page.add(ft.Column([
                self._sync_safe,
                self._layout_row,
            ], spacing=4, expand=True))
        except Exception as e:
            logger.error(f"Error en _create_layout: {e}", exc_info=True)
            show_error("Error al crear el layout de la app", e, "ControlEntradasSalidasApp._create_layout")

    def _on_sync_progress(self, msg: str):
        """Recibe mensajes de progreso del SyncManager."""
        try:
            if not self.page or not hasattr(self, 'sync_status_bar'):
                return

            is_error = 'Error' in msg and 'Error en' not in msg
            is_done = msg.endswith('finalizada') or msg.endswith('completada') or msg.endswith('completado')
            is_start = msg.endswith('completa...')
            is_empty = 'No hay' in msg or '0 registros' in msg or '0 requisiciones' in msg

            bar = self.sync_status_bar
            text = bar.content.controls[1]
            spinner = bar.content.controls[0]

            clean = msg.replace('[SYNC] ', '').replace('[SYNC-DEBUG] ', '').strip()

            if is_start:
                bar.height = 30
                spinner.visible = True
                text.value = clean
                text.color = '#BBBBBB'
                bar.bgcolor = '#2D2D2D'
            elif is_done:
                text.value = f"✓ {clean}"
                text.color = '#4CAF50'
                spinner.visible = False
                bar.bgcolor = '#1B3D1B'
                # Auto-ocultar tras 4s
                import threading
                threading.Thread(target=self._hide_sync_bar, args=(4,), daemon=True).start()
            elif is_error:
                text.value = f"✗ {clean}"
                text.color = '#F44336'
                spinner.visible = False
                bar.bgcolor = '#3D1B1B'
                threading.Thread(target=self._hide_sync_bar, args=(6,), daemon=True).start()
            else:
                bar.height = 30
                spinner.visible = True
                text.value = clean
                text.color = '#BBBBBB'
                bar.bgcolor = '#2D2D2D'

            if self.page:
                self.page.update()
        except Exception:
            pass

    def _hide_sync_bar(self, delay: float = 4):
        import time
        time.sleep(delay)
        try:
            if self.page and hasattr(self, 'sync_status_bar'):
                self.sync_status_bar.height = 0
                self.page.update()
        except Exception:
            pass

    def _register_sync_callback(self):
        """Registra el callback de progreso en el SyncManager."""
        try:
            from usr.database.sync import get_sync_manager
            sync_mgr = get_sync_manager()
            if sync_mgr:
                sync_mgr.set_sync_progress_callback(self._on_sync_progress)
        except Exception as e:
            print(f"[APP] Error registrando callback sync: {e}")

    def _on_page_resized(self, e):
        self._handle_responsive_layout(float(e.width))
        self.page.update()

    def _handle_responsive_layout(self, width):
        if width < 700:
            self.navigation_rail.visible = False
            self.page.navigation_bar = self.navigation_bar
            self.navigation_bar.visible = True
            self.content_area.border_radius = 0
        else:
            self.navigation_rail.visible = True
            self.page.navigation_bar = None
            self.navigation_bar.visible = False
            self.content_area.border_radius = ft.border_radius.only(top_left=20)

    def _on_navigation_change(self, e):
        if self.page is None:
            return
        try:
            if isinstance(e.control, ft.NavigationBar):
                index = int(e.control.selected_index)
                if index == 3:
                    self._show_more_menu()
                    return
                self.current_view_index = index
                self._show_view(index)
                return

            if isinstance(e.control, ft.NavigationRail):
                selected_dest = e.control.destinations[e.control.selected_index]
                label = selected_dest.label
                mapping = {
                    "Inventario": 0,
                    "Validación": 1,
                    "Stock": 2,
                    "Producciones": 3,
                    "Requisiciones": 4,
                    "Historial": 5,
                    "Ajustes": 6,
                    "Bandeja": 7,
                }
                index = mapping.get(label)
                if index is None:
                    return
                self.current_view_index = index
                self._show_view(index)
        except Exception as e:
            logger.error(f"Error en _on_navigation_change: {e}", exc_info=True)
            show_error("Error al cambiar de vista", e, "ControlEntradasSalidasApp._on_navigation_change")

    def _show_more_menu(self):
        if self.page is None:
            return
        try:
            opciones = [("factory", "Producciones", 3), ("assignment", "Requisiciones", 4), ("history", "Historial", 5), ("settings", "Ajustes", 6), ("mail", "Bandeja", 7)]

            is_dark = self.page.theme_mode == ft.ThemeMode.DARK
            theme_icon = ft.Icons.LIGHT_MODE if is_dark else ft.Icons.DARK_MODE
            theme_label = "Modo Claro" if is_dark else "Modo Oscuro"

            def on_toggle_theme(e):
                self.page.close(self.bottom_sheet)
                self._toggle_theme()

            def on_nav(e, idx):
                self.page.close(self.bottom_sheet)
                self._show_view(idx)

            menu_content = ft.Column(spacing=0, controls=[
                ft.Container(
                    content=ft.Row([ft.Icon(theme_icon, size=24), ft.Text(theme_label, size=16)], spacing=15),
                    padding=ft.padding.all(15),
                    on_click=on_toggle_theme,
                ),
                ft.Divider(height=1, color='#3D3D3D'),
                *[
                    ft.Container(
                        content=ft.Row([ft.Icon(icon, size=24), ft.Text(label, size=16)], spacing=15),
                        padding=ft.padding.all(15),
                        on_click=lambda e, i=idx: on_nav(e, i),
                    )
                    for icon, label, idx in opciones
                ],
            ])

            self.bottom_sheet = ft.BottomSheet(content=ft.Container(content=menu_content, padding=ft.padding.only(bottom=20)), open=True)
            self.page.open(self.bottom_sheet)
        except Exception as e:
            logger.error(f"Error en _show_more_menu: {e}", exc_info=True)
            show_error("Error al abrir el menú de más opciones", e, "ControlEntradasSalidasApp._show_more_menu")

    def _show_view(self, index: int):
        try:
            if not self.views or index < 0 or index >= len(self.views):
                keys = list(range(len(self.views))) if self.views else "None"
                self.content_area.content = ft.Container(
                    content=ft.Text(f"Error: Vista {index} no encontrada. Keys: {keys}", color=ft.Colors.RED),
                    alignment=ft.alignment.center, expand=True,
                )
                self.page.update()
                return
            view = self.views[index]

            if self.current_view:
                self.current_view.visible = False

            self.content_area.content = view
            view.visible = True
            self.current_view = view
            self.current_view_index = index

            if self.navigation_bar:
                if index < 3:
                    self.navigation_bar.selected_index = index
                else:
                    self.navigation_bar.selected_index = 3
        except Exception as e:
            logger.error(f"Error en _show_view({index}): {e}", exc_info=True)
            show_error(f"Error al mostrar la vista {index}", e, "ControlEntradasSalidasApp._show_view")
            return

        if hasattr(view, '_update_connection_indicator'):
            try:
                if hasattr(view, '_connection_indicator') and view._connection_indicator in self.page.controls:
                    view._update_connection_indicator()
            except:
                pass

        self.page.update()
