import flet as ft
print(">>> FLET IMPORTED", flush=True)

import traceback
import time
import asyncio

print(">>> ALL IMPORTS READY", flush=True)


def log_debug(msg):
    ts = time.strftime("%H:%M:%S")
    print(f"[DEBUG] {msg}", flush=True)


def get_theme_colors(page):
    is_dark = page.theme_mode == ft.ThemeMode.DARK
    return {
        'bg': '#121212' if is_dark else '#F5F5F5',
        'surface': '#1E1E1E' if is_dark else '#FFFFFF',
        'surface_container': '#2D2D2D' if is_dark else '#FAFAFA',
        'text_primary': '#FFFFFF' if is_dark else '#1A1A1A',
        'text_secondary': '#B0B0B0' if is_dark else '#666666',
        'accent': '#BB86FC' if is_dark else '#6200EE',
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
        self.page.title = self.settings.FLET_APP_NAME
        self.page.theme_mode = ft.ThemeMode.DARK
        self.page.padding = 0
        self.page.spacing = 0
        self.page.expand = True

        self._setup_theme()
        self._create_layout()
        print(">>> LAYOUT CREATED")
        self._show_view(0)
        print(">>> VIEW SHOWN")
        self._handle_resize()
        self.page.update()
        print(">>> ALL DONE")

    def _setup_theme(self):
        self.page.theme = ft.Theme(color_scheme_seed=ft.Colors.DEEP_PURPLE_700, visual_density=ft.VisualDensity.COMFORTABLE, use_material3=True)
        self.page.bgcolor = '#1A1A1A'
    
    def _toggle_theme(self, e=None):
        is_dark = self.page.theme_mode != ft.ThemeMode.DARK
        self.page.theme_mode = ft.ThemeMode.DARK if is_dark else ft.ThemeMode.LIGHT
        self.page.bgcolor = '#1A1A1A' if is_dark else '#F5F5F5'
        if hasattr(self, 'content_area'):
            self.content_area.bgcolor = '#252525' if is_dark else '#FFFFFF'
        if self.current_view and hasattr(self.current_view, 'on_theme_change'):
            self.current_view.on_theme_change()
        self.page.update()

    def _create_layout(self):
        self.content_area = ft.Container(expand=True, padding=0, bgcolor='#252525', border_radius=ft.BorderRadius.only(top_left=20) if self.page.width >= 700 else 0)

        self.theme_toggle = ft.IconButton(icon=ft.Icons.LIGHT_MODE, tooltip="Modo Claro", on_click=self._toggle_theme, icon_color=ft.Colors.AMBER)

        self.navigation_rail = ft.NavigationRail(
            selected_index=0, extended=False, label_type=ft.NavigationRailLabelType.ALL, min_width=100, bgcolor='#1E1E1E', leading=self.theme_toggle,
            destinations=[
                ft.NavigationRailDestination(icon="shopping_cart_outlined", selected_icon="shopping_cart", label="Inventario"),
                ft.NavigationRailDestination(icon="checklist_outlined", selected_icon="checklist", label="Validación"),
                ft.NavigationRailDestination(icon="warehouse_outlined", selected_icon="warehouse", label="Stock"),
                ft.NavigationRailDestination(icon="local_shipping_outlined", selected_icon="local_shipping", label="Requisiciones"),
                ft.NavigationRailDestination(icon="history_outlined", selected_icon="history", label="Historial"),
                ft.NavigationRailDestination(icon="settings_outlined", selected_icon="settings", label="Ajustes"),
            ], on_change=self._on_navigation_change,
        )

        self.navigation_bar = ft.NavigationBar(
            visible=False, bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
            destinations=[
                ft.NavigationBarDestination(icon="shopping_cart_outlined", label="Inventario"),
                ft.NavigationBarDestination(icon="checklist_outlined", label="Validar"),
                ft.NavigationBarDestination(icon="warehouse_outlined", label="Stock"),
                ft.NavigationBarDestination(icon="local_shipping_outlined", label="Requisiciones"),
            ], on_change=self._on_navigation_change,
        )

        self._layout_row = ft.SafeArea(content=ft.Row([self.navigation_rail, self.content_area], expand=True, spacing=0), expand=True, minimum_padding=ft.Padding.only(top=5))
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
        opciones = [("assignment", "Requisiciones", 3), ("history", "Historial", 4), ("settings", "Ajustes", 5)]
        
        menu_content = ft.Column(spacing=0, controls=[
            ft.Container(content=ft.Row([ft.Icon(ft.Icons.LIGHT_MODE if self.page.theme_mode == ft.ThemeMode.DARK else ft.Icons.DARK_MODE, size=24), ft.Text("Modo Oscuro" if self.page.theme_mode == ft.ThemeMode.DARK else "Modo Claro", size=16)], spacing=15), padding=ft.padding.all(15), on_click=self._toggle_theme),
            ft.Divider(height=1, color='#3D3D3D'),
            *[ft.Container(content=ft.Row([ft.Icon(icon, size=24), ft.Text(label, size=16)], spacing=15), padding=ft.padding.all(15), on_click=lambda _, i=idx: self._show_view(i)) for icon, label, idx in opciones]
        ])
        
        self.bottom_sheet = ft.BottomSheet(content=ft.Container(content=menu_content, padding=ft.padding.only(bottom=20)), open=True)
        self.page.open(self.bottom_sheet)

    def _show_view(self, index: int):
        print(f">>> SHOW VIEW {index}")
        if self.current_view: 
            self.current_view.visible = False
        view = self.views[index]
        self.content_area.content = view
        view.visible = True
        self.current_view = view
        self.current_view_index = index
        self.navigation_rail.selected_index = index
        if self.page.navigation_bar: 
            self.page.navigation_bar.selected_index = index
        self.page.update()


def show_error(page, msg):
    page.clean()
    page.add(ft.Container(
        bgcolor="#121212", expand=True,
        content=ft.Column([
            ft.Container(height=40),
            ft.Icon(ft.Icons.ERROR_OUTLINE, size=80, color=ft.Colors.RED_400),
            ft.Container(height=20),
            ft.Text("Algo salió mal!", size=28, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE),
            ft.Container(height=10),
            ft.Container(content=ft.Text(msg[:100], size=13, color=ft.Colors.RED_200, selectable=True), padding=15, bgcolor="#1E1E1E", border_radius=10),
            ft.Container(height=30),
            ft.Button("REINTENTAR", on_click=lambda _: main(page), bgcolor=ft.Colors.DEEP_PURPLE_600, color=ft.Colors.WHITE, height=45),
        ], horizontal_alignment="center", spacing=0),
        alignment="center", padding=30
    ))
    page.update()


async def main(page: ft.Page):
    print(">>> main() CALLED")
    
    try:
        # Loading screen
        logo = ft.Container(content=ft.Column([
            ft.Icon(ft.Icons.INVENTORY_2, size=60, color=ft.Colors.DEEP_PURPLE_300),
            ft.Text("Lycoris", size=32, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE),
            ft.Text("Control", size=16, color=ft.Colors.DEEP_PURPLE_200),
        ], horizontal_alignment="center"), alignment="center")
        
        step_text = ft.Text("1/5", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE)
        status_text = ft.Text("Cargando...", size=14, color=ft.Colors.GREY)
        
        loading = ft.Column([logo, ft.Container(height=30), ft.ProgressRing(stroke_width=3, color=ft.Colors.DEEP_PURPLE_400), step_text, status_text], horizontal_alignment="center", spacing=10)
        
        page.add(ft.Container(bgcolor="#121212", expand=True, content=loading, alignment="center", padding=40))
        page.update()
        
        # Step 1: Config
        step_text.value = "2/5"
        status_text.value = "Configuración..."
        page.update()
        
        from config.config import get_settings
        settings = get_settings()
        status_text.value = "✓ Lista"
        
        # Step 2: Database
        step_text.value = "3/5"
        status_text.value = "Base de datos..."
        page.update()
        
        from usr.database.base import get_engine, get_session_local
        from usr.database.sync import init_sync_manager
        sync_manager = init_sync_manager(get_engine)
        status_text.value = "✓ Conectado"
        
        # Step 3: Views import
        step_text.value = "4/5"
        status_text.value = "Módulos..."
        page.update()
        
        from usr.views import InventarioView, ValidacionView, StockView, ConfiguracionView, HistorialFacturasView, RequisicionesView
        status_text.value = "✓ Cargado"
        
        # Step 4: Create views
        step_text.value = "5/5"
        status_text.value = "Creando..."
        page.update()
        
        inventario_view = InventarioView()
        requisiciones_view = RequisicionesView()
        requisiciones_view.inventario_view = inventario_view
        status_text.value = "✓ Creado"
        
        vistas = {0: inventario_view, 1: ValidacionView(), 2: StockView(), 3: requisiciones_view, 4: HistorialFacturasView(), 5: ConfiguracionView()}
        
        app_instance = ControlEntradasSalidasApp()
        requisiciones_view.app_controller = app_instance
        
        # Done
        step_text.value = "Listo!"
        status_text.value = "Iniciando..."
        page.update()
        
        await app_instance.arrancar_interfaz(page, settings, vistas)
        
        print(">>> APP STARTED")
        
    except Exception as e:
        print(f">>> ERROR: {e}")
        traceback.print_exc()
        show_error(page, str(e)[:100])


if __name__ == "__main__":
    print(">>> RUNNING")
    ft.app(target=main)