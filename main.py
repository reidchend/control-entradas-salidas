import flet as ft
import os
from config.config import get_settings
from app.views import InventarioView, ValidacionView, StockView, ConfiguracionView, HistorialFacturasView

settings = get_settings()

class ControlEntradasSalidasApp:
    def __init__(self):
        self.page = None
        self.navigation_rail = None
        self.navigation_bar = None
        self.content_area = None
        self.current_view = None
        self.views = None

    def main(self, page: ft.Page):
        self.page = page
        self.page.window_icon = settings.FLET_APP_ICON
        self.page.title = settings.FLET_APP_NAME
        self.page.update()
 
        self.page.theme_mode = ft.ThemeMode.LIGHT
        self.page.padding = 0
        self.page.spacing = 0

        # 2. CONFIGURACIÓN DE PANTALLA DE CARGA (SPLASH)
        self.page.splash = ft.Container(
            content=ft.Column(
                [
                    ft.Icon(ft.icons.INVENTORY_2_ROUNDED, size=60, color="#6750A4"),
                    ft.ProgressRing(width=40, color="#6750A4"),
                    ft.Text("Cargando sistema...", size=16, weight="bold")
                ],
                alignment=ft.MainAxisAlignment.CENTER,
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            bgcolor=ft.colors.WHITE,
            expand=True,
        )
        self.page.update()

        # Instanciar vistas
        self.views = {
            0: InventarioView(),
            1: ValidacionView(),
            2: StockView(),
            3: HistorialFacturasView(),
            4: ConfiguracionView(),
        }

        self._setup_theme()
        self._create_layout()
        self._show_view(0)
        self._handle_resize()

        # 3. QUITAR PANTALLA DE CARGA AL FINALIZAR
        self.page.splash = None
        self.page.update()

    def _setup_theme(self):
        self.page.theme = ft.Theme(
            color_scheme=ft.ColorScheme(
                primary="#6750A4",
                on_primary="#FFFFFF",
                surface="#FFFBFE",
            ),
            use_material3=True,
        )

    def _create_layout(self):
        self.content_area = ft.Container(
            expand=True,
            padding=ft.padding.all(16),
            border_radius=ft.border_radius.all(12),
            bgcolor=ft.colors.WHITE,
        )

        self.navigation_rail = ft.NavigationRail(
            selected_index=0,
            label_type=ft.NavigationRailLabelType.ALL,
            destinations=[
                ft.NavigationRailDestination(icon=ft.icons.INVENTORY, label="Inventario"),
                ft.NavigationRailDestination(icon=ft.icons.FACT_CHECK, label="Validación"),
                ft.NavigationRailDestination(icon=ft.icons.STORAGE, label="Stock"),
                ft.NavigationRailDestination(icon=ft.icons.HISTORY, label="Historial"),
                ft.NavigationRailDestination(icon=ft.icons.SETTINGS, label="Config"),
            ],
            on_change=self._on_navigation_change,
        )

        self.navigation_bar = ft.NavigationBar(
            destinations=[
                ft.NavigationDestination(icon=ft.icons.INVENTORY, label="Inventario"),
                ft.NavigationDestination(icon=ft.icons.FACT_CHECK, label="Validación"),
                ft.NavigationDestination(icon=ft.icons.STORAGE, label="Stock"),
                ft.NavigationDestination(icon=ft.icons.HISTORY, label="Historial"),
                ft.NavigationDestination(icon=ft.icons.SETTINGS, label="Config"),
            ],
            on_change=self._on_navigation_change,
            label_behavior=ft.NavigationBarLabelBehavior.ONLY_SHOW_SELECTED,
        )

        self._layout_row = ft.Row(
            [self.navigation_rail, ft.VerticalDivider(width=1), self.content_area],
            expand=True,
            spacing=0,
        )
        self.page.add(self._layout_row)

    def _handle_resize(self):
        def on_resize(e):
            if self.page.width < 600:
                self._switch_to_mobile_layout()
            else:
                self._switch_to_desktop_layout()
        self.page.on_resized = on_resize
        on_resize(None)

    def _switch_to_mobile_layout(self):
        self.navigation_rail.visible = False
        self._layout_row.controls = [self.content_area]
        self.page.navigation_bar = self.navigation_bar
        self.page.update()

    def _switch_to_desktop_layout(self):
        self.navigation_rail.visible = True
        self._layout_row.controls = [self.navigation_rail, ft.VerticalDivider(width=1), self.content_area]
        self.page.navigation_bar = None
        self.page.update()

    def _on_navigation_change(self, e):
        index = e.control.selected_index
        self._show_view(index)

    def _show_view(self, index: int):
        if self.current_view:
            self.current_view.visible = False
        
        view = self.views[index]
        self.content_area.content = view
        view.visible = True
        self.current_view = view
        
        self.navigation_rail.selected_index = index
        if self.page.navigation_bar:
            self.page.navigation_bar.selected_index = index
        self.page.update()

def _per_page_main(page: ft.Page):
    app = ControlEntradasSalidasApp()
    app.main(page)

if __name__ == "__main__":
    script_dir = os.path.dirname(__file__)
    assets_path = os.path.join(script_dir, "assets")
    
    # Validación segura del puerto de la App
    raw_port = os.getenv("PORT") or settings.FLET_WEB_PORT
    clean_port = int(str(raw_port).strip()) if raw_port and str(raw_port).strip() else 8502
    
    ft.app(
        target=_per_page_main,
        view=ft.AppView.WEB_BROWSER,
        port=clean_port,
        host="0.0.0.0",
        assets_dir=assets_path 
    )