import flet as ft
print(">>> FLET IMPORTED", flush=True)
import traceback
import sys
import os
import time
import asyncio

_debug_lines = []

def log_debug(msg):
    """Log para debug"""
    ts = time.strftime("%H:%M:%S")
    print(f"[DEBUG] {msg}", flush=True)





def log_debug(msg):
    """Log para debug"""
    ts = time.strftime("%H:%M:%S")
    print(f"[DEBUG] {msg}", flush=True)





def get_theme_colors(page):
    """Retorna colores según el tema actual"""
    is_dark = page.theme_mode == ft.ThemeMode.DARK
    return {
        'bg': '#121212' if is_dark else '#F5F5F5',
        'surface': '#1E1E1E' if is_dark else '#FFFFFF',
        'surface_container': '#2D2D2D' if is_dark else '#FAFAFA',
        'text_primary': '#FFFFFF' if is_dark else '#1A1A1A',
        'text_secondary': '#B0B0B0' if is_dark else '#666666',
        'accent': '#BB86FC' if is_dark else '#6200EE',
        'nav_bg': '#1E1E1E' if is_dark else '#F3E5F5',
        'card_bg': '#2D2D2D' if is_dark else '#FFFFFF',
        'border': '#3D3D3D' if is_dark else '#E0E0E0',
        'blue_50': '#3D3D5C' if is_dark else '#E3F2FD',
        'green_700': '#4CAF50' if is_dark else '#388E3C',
        'red_600': '#F44336' if is_dark else '#D32F2F',
        'orange_50': '#4A3D2D' if is_dark else '#FFF3E0',
    }


class ControlEntradasSalidasApp:
    def __init__(self):
        self.page = None
        self.navigation_rail = None
        self.navigation_bar = None
        self.content_area = None
        self.current_view = None
        self.current_view_index = 0
        self.views = None
        self._layout_row = None
        self.settings = None

    async def arrancar_interfaz(self, page: ft.Page, settings, vistas_cargadas):
        self.page = page
        self.settings = settings
        self.views = vistas_cargadas
        
        self.page.clean()

        try:
            self.page.title = self.settings.FLET_APP_NAME
        except Exception as e:
            print(f"Error title: {e}")
            
        self.page.theme_mode = ft.ThemeMode.DARK
        self.page.padding = 0
        self.page.spacing = 0
        self.page.expand = True

        self._setup_theme()
        
        self._create_layout()
        self._show_view(0)
        self._handle_resize()
        self.page.update()

    def _setup_theme(self):
        self.page.theme = ft.Theme(
            color_scheme_seed=ft.Colors.DEEP_PURPLE_700, 
            visual_density=ft.VisualDensity.COMFORTABLE,
            use_material3=True,
        )
        self.page.bgcolor = '#1A1A1A'
    
    def _toggle_theme(self, e=None):
        if self.page.theme_mode == ft.ThemeMode.DARK:
            self.page.theme_mode = ft.ThemeMode.LIGHT
            is_dark = False
        else:
            self.page.theme_mode = ft.ThemeMode.DARK
            is_dark = True
        
        page_bg = '#1A1A1A' if is_dark else '#F5F5F5'
        content_bg = '#252525' if is_dark else '#FFFFFF'
        nav_bg = '#1E1E1E' if is_dark else '#F3E5F5'
        
        self.page.bgcolor = page_bg
        
        if hasattr(self, 'content_area'):
            self.content_area.bgcolor = content_bg
        
        if hasattr(self, 'navigation_rail'):
            self.navigation_rail.bgcolor = nav_bg
        
        if hasattr(self, 'navigation_bar'):
            self.navigation_bar.bgcolor = nav_bg
        
        if hasattr(self, 'theme_toggle'):
            self.theme_toggle.icon = ft.Icons.DARK_MODE if not is_dark else ft.Icons.LIGHT_MODE
            self.theme_toggle.icon_color = ft.Colors.AMBER if is_dark else ft.Colors.BLUE_GREY_700
            self.theme_toggle.tooltip = "Modo Oscuro" if not is_dark else "Modo Claro"
        
        if self.current_view and hasattr(self.current_view, 'on_theme_change'):
            self.current_view.on_theme_change()
        
        try:
            self.page.update()
        except:
             pass

    def _create_layout(self):
        self.content_area = ft.Container(
            expand=True, 
            padding=0, 
            bgcolor='#252525',
            border_radius=ft.border_radius.only(top_left=20) if self.page.width >= 700 else 0
        )

        self.theme_toggle = ft.IconButton(
            icon=ft.Icons.LIGHT_MODE,
            tooltip="Modo Claro",
            on_click=self._toggle_theme,
            icon_color=ft.Colors.AMBER,
        )

        self.navigation_rail = ft.NavigationRail(
            selected_index=0,
            extended=False,
            label_type=ft.NavigationRailLabelType.ALL,
            min_width=100,
            bgcolor='#1E1E1E',
            leading=self.theme_toggle,
            destinations=[
                ft.NavigationRailDestination(icon="shopping_cart_outlined", selected_icon="shopping_cart", label="Inventario"),
                ft.NavigationRailDestination(icon="checklist_outlined", selected_icon="checklist", label="Validación"),
                ft.NavigationRailDestination(icon="warehouse_outlined", selected_icon="warehouse", label="Stock"),
                ft.NavigationRailDestination(icon="local_shipping_outlined", selected_icon="local_shipping", label="Requisiciones"),
                ft.NavigationRailDestination(icon="history_outlined", selected_icon="history", label="Historial"),
                ft.NavigationRailDestination(icon="settings_outlined", selected_icon="settings", label="Ajustes"),
            ],
            on_change=self._on_navigation_change,
        )

        self.navigation_bar = ft.NavigationBar(
            visible=False,
            bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
            destinations=[
                ft.NavigationBarDestination(icon="shopping_cart_outlined", label="Inventario"),
                ft.NavigationBarDestination(icon="checklist_outlined", label="Validar"),
                ft.NavigationBarDestination(icon="warehouse_outlined", label="Stock"),
                ft.NavigationBarDestination(icon="local_shipping_outlined", label="Requisiciones"),
            ],
            on_change=self._on_navigation_change,
        )

        self._layout_row = ft.SafeArea(
            content=ft.Row(
                [self.navigation_rail, self.content_area],
                expand=True,
                spacing=0,
            ),
            expand=True,
            minimum_padding=ft.padding.only(top=5)
        )
        self.page.add(self._layout_row)

    def _handle_resize(self):
        def on_resize(e):
            if self.page.width < 700:
                self.navigation_rail.visible = False
                self.page.navigation_bar = self.navigation_bar
                self.page.navigation_bar.visible = True
            else:
                self.navigation_rail.visible = True
                self.page.navigation_bar = None
            self.page.update()
        
        self.page.on_resized = on_resize
        on_resize(None)

    def _on_navigation_change(self, e):
        index = int(e.control.selected_index)
        
        if self.page.width < 700 and index == 3:
            self._show_more_menu()
            self.navigation_bar.selected_index = self.current_view_index
            return
        
        self.current_view_index = index
        self._show_view(index)

    def _show_more_menu(self):
        def on_option_click(view_index):
            self._show_view(view_index)
            self.page.close(self.bottom_sheet)
            self.navigation_bar.selected_index = 0
        
        opciones = [
            ("assignment", "Requisiciones", 3),
            ("history", "Historial", 4),
            ("settings", "Ajustes", 5),
        ]
        
        colors = get_theme_colors(self.page)
        
        def on_toggle_theme(e):
            self._toggle_theme()
            self.page.close(self.bottom_sheet)
        
        is_dark = self.page.theme_mode == ft.ThemeMode.DARK
        theme_icon = ft.Icons.LIGHT_MODE if is_dark else ft.Icons.DARK_MODE
        theme_text = "Modo Claro" if is_dark else "Modo Oscuro"
        
        menu_content = ft.Column(
            spacing=0,
            controls=[
                ft.Container(
                    content=ft.Row([
                        ft.Icon(theme_icon, size=24),
                        ft.Text(theme_text, size=16),
                    ], spacing=15),
                    padding=ft.padding.all(15),
                    on_click=on_toggle_theme,
                ),
                ft.Divider(height=1, color=colors['border']),
                *[
                    ft.Container(
                        content=ft.Row([
                            ft.Icon(icon, size=24),
                            ft.Text(label, size=16),
                        ], spacing=15),
                        padding=ft.padding.all(15),
                        on_click=lambda _, i=view_idx: on_option_click(i),
                    )
                    for icon, label, view_idx in opciones
                ]
            ]
        )
        
        self.bottom_sheet = ft.BottomSheet(
            content=ft.Container(
                content=menu_content,
                padding=ft.padding.only(bottom=20),
            ),
            open=True,
        )
        self.page.open(self.bottom_sheet)

    def _show_view(self, index: int):
        if self.current_view: 
            self.current_view.visible = False
        view = self.views[index]
        self.content_area.content = view
        view.visible = True
        self.current_view = view
        self.current_view_index = index
        
        view.bgcolor = '#1A1A1A' if self.page.theme_mode == ft.ThemeMode.DARK else '#F5F5F5'
        
        self.navigation_rail.selected_index = index
        if self.page.navigation_bar: 
            self.page.navigation_bar.selected_index = index
        self.page.update()


def mostrar_error_pantalla(page: ft.Page, titulo: str, mensaje: str, detalles: str = ""):
    """Muestra pantalla de error con opción de reintentar"""
    page.clean()
    
    debug_lines_text = "\n".join(_debug_lines[-15:]) if _debug_lines else "No debug log"
    
    page.add(ft.Container(
        content=ft.Column([
            ft.Icon(name=ft.Icons.ERROR, size=50, color=ft.Colors.RED),
            ft.Text(titulo, size=20, weight=ft.FontWeight.BOLD, color=ft.Colors.RED),
            ft.Text(mensaje, size=14),
            ft.Container(height=20),
            ft.ElevatedButton(
                "Reintentar",
                on_click=lambda _: main(page)
            ),
            ft.Container(height=20),
            ft.Divider(),
            ft.Text("Debug Log (últimos 15):", size=12, weight=ft.FontWeight.BOLD),
            ft.Container(
                content=ft.Text(debug_lines_text, size=9, font_family="monospace", selectable=True),
                bgcolor=ft.Colors.BLACK12,
                padding=10,
                border_radius=5,
                height=150,
            ),
            ft.Divider(),
            ft.Text("Detalles técnicos:", size=12, weight=ft.FontWeight.BOLD),
            ft.Text(detalles, size=10, font_family="monospace", selectable=True),
        ], scroll=ft.ScrollMode.AUTO),
        padding=30,
        alignment=ft.alignment.top_center,
    ))
    page.update()


async def main(page: ft.Page):
    print(">>> main() CALLED", flush=True)
    log_debug("=== main() ENTERED ===")
    
    try:
        # ULTRA SIMPLE - Just one text
        w = page.width if page.width else 360
        h = page.height if page.height else 640
        
        page.add(ft.Text(f"HELLO w={w} h={h}", size=40, color=ft.Colors.RED))
        page.update()
        print(">>> FIRST TEXT ADDED", flush=True)
        
        await asyncio.sleep(2)
        
        # Add screen info
        page.add(ft.Text(f"SIZE={page.width}x{page.height}", size=30, color=ft.Colors.GREEN))
        page.update()
        
        # Continue loading the app normally
        page.add(ft.Text("LOADING APP...", size=24, color=ft.Colors.BLUE))
        page.update()
        
        # Add a simple "NEXT" text to see if we get here
        await asyncio.sleep(1)
        page.add(ft.Text("S1 NEXT", size=30, color=ft.Colors.ORANGE))
        page.update()
        
        # Now load the rest of the app
        step_indicator = ft.Text("S0", size=32, weight=ft.FontWeight.BOLD, color=ft.Colors.YELLOW_200)
        status_log = ft.Text("Config...", size=20, color=ft.Colors.WHITE)
        debug_info = ft.Text("", size=14, color=ft.Colors.CYAN)
        
        loading = ft.Column([step_indicator, status_log, debug_info], spacing=15)
        loading_container = ft.Container(
            bgcolor=ft.Colors.BLACK,
            expand=True,
            content=loading,
            padding=40,
            alignment=ft.alignment.center
        )
        page.add(loading_container)
        
        step_indicator.value = "S1"
        status_log.value = "Config..."
        debug_info.value = "loading..."
        page.update()
        
        try:
            from config.config import get_settings
            settings = get_settings()
            status_log.value = "OK"
            page.update()
        except Exception as e:
            status_log.value = f"ERR cfg: {str(e)[:30]}"
            debug_info.value = str(e)
            page.update()
            print(f">>> CONFIG ERROR: {e}")
            await asyncio.sleep(5)
            return
        
        step_indicator.value = "S2"
        status_log.value = "DB..."
        debug_info.value = "connecting..."
        page.update()
        
        try:
            from usr.database.base import get_engine, get_session_local
            from usr.database.sync import init_sync_manager
            sync_manager = init_sync_manager(get_engine)
            status_log.value = "OK"
            page.update()
        except Exception as e:
            status_log.value = f"ERR DB: {str(e)[:30]}"
            debug_info.value = str(e)
            page.update()
            print(f">>> DB ERROR: {e}")
            await asyncio.sleep(5)
            return
        
        step_indicator.value = "S3"
        status_log.value = "Views..."
        debug_info.value = "loading..."
        page.update()
        
        try:
            from usr.views import InventarioView, ValidacionView, StockView, ConfiguracionView, HistorialFacturasView, RequisicionesView
            status_log.value = "OK"
            page.update()
        except Exception as e:
            status_log.value = f"ERR view: {str(e)[:30]}"
            debug_info.value = str(e)
            page.update()
            print(f">>> VIEW ERROR: {e}")
            await asyncio.sleep(5)
            return
        
        step_indicator.value = "S4"
        status_log.value = "Creating..."
        page.update()
        
        try:
            inventario_view = InventarioView()
            requisiciones_view = RequisicionesView()
            requisiciones_view.inventario_view = inventario_view
            status_log.value = "OK"
            page.update()
        except Exception as e:
            status_log.value = f"ERR make: {str(e)[:30]}"
            debug_info.value = str(e)
            page.update()
            print(f">>> MAKE ERROR: {e}")
            await asyncio.sleep(5)
            return
        
        vistas = {
            0: inventario_view,
            1: ValidacionView(),
            2: StockView(),
            3: requisiciones_view,
            4: HistorialFacturasView(),
            5: ConfiguracionView(),
        }
        
        app_instance = ControlEntradasSalidasApp()
        requisiciones_view.app_controller = app_instance
        
        step_indicator.value = "S5"
        status_log.value = "Starting UI..."
        page.update()
        
        await app_instance.arrancar_interfaz(page, settings, vistas)
        
        status_log.value = "DONE!"
        page.update()
        print(">>> APP STARTED")
        
    except Exception as e:
        error_msg = f"ERROR: {str(e)}"
        print(f">>> {error_msg}", flush=True)
        traceback.print_exc()
        
        page.clean()
        page.add(ft.Container(
            bgcolor=ft.Colors.BLACK,
            expand=True,
            content=ft.Column([
                ft.Icon(ft.Icons.ERROR_OUTLINE, size=60, color=ft.Colors.RED),
                ft.Text("Oops!", size=30, weight=ft.FontWeight.BOLD, color=ft.Colors.RED),
                ft.Container(height=20),
                ft.Text(error_msg, size=16, color=ft.Colors.WHITE, selectable=True),
                ft.Container(height=30),
                ft.ElevatedButton(
                    "REINTENTAR",
                    on_click=lambda _: main(page),
                    bgcolor=ft.Colors.DEEP_PURPLE_700,
                    color=ft.Colors.WHITE
                ),
            ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),
            alignment=ft.alignment.center,
            padding=40
        ))
        page.update()


if __name__ == "__main__":
    print(">>> RUNNING FT.APP", flush=True)
    try:
        ft.app(target=main)
    except Exception as e:
        print(f">>> FT.APP CRASHED: {e}", flush=True)
        traceback.print_exc()
        
        # Can't show GUI without page, so just print
        print("="*40)
        print("APP CRASHED BEFORE STARTING")
        print(f"ERROR: {e}")
        print("="*40)