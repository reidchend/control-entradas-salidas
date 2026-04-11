import flet as ft
print(">>> FLET IMPORTED", flush=True)
import traceback
import sys
import os
import time
import asyncio
print(">>> ALL IMPORTS READY", flush=True)


_debug_file = "/sdcard/Android/data/com.reidchend.control_entradas_salidas/files/debug.log"

def log_debug(msg):
    """Log para debug en archivo"""
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}\n"
    print(f"[DEBUG] {msg}", flush=True)
    try:
        with open(_debug_file, "a") as f:
            f.write(line)
    except Exception as e:
        print(f"[FILE ERROR] {e}", flush=True)


def log_error(msg):
    log_debug(f"ERROR: {msg}")


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
    
    page.expand = True
    page.bgcolor = "#1A1A1A"
    page.padding = 0
    page.spacing = 0
    page.clean()
    log_debug("page cleaned")
    
    page.add(ft.Text("STARTING...", color=ft.Colors.WHITE))
    page.update()
    log_debug("FIRST TEXT ADDED")
    await asyncio.sleep(0.05)
    page.update()
    log_debug("FIRST UPDATE DONE")
    
    step_indicator = ft.Text("S0", size=14, color=ft.Colors.DEEP_PURPLE_300)
    status_log = ft.Text("Init...", size=14, color=ft.Colors.WHITE)
    debug_info = ft.Text("", size=10, color=ft.Colors.GREY)
    
    loading = ft.Column([step_indicator, status_log, debug_info], spacing=5)
    page.add(loading)
    page.update()
    log_debug("INITIAL RENDER DONE")
    
    await asyncio.sleep(0.1)
    page.update()
    log_debug("AFTER SLEEP")

    try:
        step_indicator.value = "S1"
        debug_info.value = "config.config.get_settings()..."
        page.update()
        try:
            from config.config import get_settings
            settings = get_settings()
            debug_info.value = f"OK: {settings.FLET_APP_NAME}"
            page.update()
            log_debug(f"Config loaded: {settings.FLET_APP_NAME}")
        except Exception as e:
            debug_info.value = f"ERROR: {str(e)[:50]}"
            page.update()
            raise
        
        step_indicator.value = "Step: 2/5"
        status_log.value = "Conectando base de datos..."
        debug_info.value = "usr.database.base..."
        page.update()
        try:
            from usr.database.base import get_engine, get_session_local
            from usr.database.sync import init_sync_manager, get_sync_manager
            sync_manager = init_sync_manager(get_engine)
            debug_info.value = "DB connected OK"
            page.update()
            log_debug("DB connected")
        except Exception as e:
            debug_info.value = f"ERROR: {str(e)[:50]}"
            page.update()
            raise
        
        step_indicator.value = "Step: 3/5"
        status_log.value = "Cargando módulos de vistas..."
        debug_info.value = "from usr.views import..."
        page.update()
        log_debug("Step 3: importing views...")
        try:
            from usr.views import InventarioView, ValidacionView, StockView, ConfiguracionView, HistorialFacturasView, RequisicionesView
            debug_info.value = "Views import OK"
            page.update()
            log_debug("Views imported OK")
        except Exception as e:
            debug_info.value = f"ERROR import: {str(e)[:80]}"
            page.update()
            log_error(f"Import error: {e}")
            raise
        
        step_indicator.value = "Step: 4/5"
        status_log.value = "Creando vistas..."
        debug_info.value = "InventarioView()..."
        page.update()
        log_debug("Step 4: creating InventarioView...")
        
        try:
            inventario_view = InventarioView()
            log_debug("InventarioView created")
            debug_info.value = "RequisicionesView()..."
            page.update()
            
            log_debug("Creating RequisicionesView...")
            requisiciones_view = RequisicionesView()
            requisiciones_view.inventario_view = inventario_view
            log_debug("RequisicionesView created")
            
            debug_info.value = "Vistas OK"
            page.update()
        except Exception as e:
            debug_info.value = f"ERROR view: {str(e)[:60]}"
            page.update()
            log_error(f"View creation error: {e}")
            raise
        
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
        
        try:
            import threading
            def delayed_sync():
                import time
                time.sleep(3)
                try:
                    sync_manager.start_background_sync(get_session_local)
                    print("[SYNC] Background sync started")
                except Exception as e:
                    print(f"[SYNC] Background error: {e}")
                    import traceback
                    traceback.print_exc()
            
            threading.Thread(target=delayed_sync, daemon=True).start()
        except Exception as e:
            print(f"[SYNC] Error: {e}")
        
        step_indicator.value = "Step: 5/5"
        status_log.value = "Cargando interfaz..."
        debug_info.value = "app_instance.arrancar_interfaz()"
        page.update()
        log_debug("Starting interface...")
        
        await app_instance.arrancar_interfaz(page, settings, vistas)
        
        status_log.value = "¡Listo! - App iniciada"
        debug_info.value = "Todos los módulos cargados"
        step_indicator.value = "COMPLETO"
        page.update()
        log_debug("DONE - App started successfully")

    except Exception as e:
        error_stack = traceback.format_exc()
        log_debug(f"ERROR: {e}")
        log_debug(error_stack)
        
        mostrar_error_pantalla(
            page,
            "Error al iniciar",
            str(e),
            error_stack
        )


if __name__ == "__main__":
    ft.app(target=main)