import flet as ft
import os
import time
import traceback
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
        self.splash_container = None # Nueva forma de manejar el splash

    def main(self, page: ft.Page):
        self.page = page
        self.page.window_icon = settings.FLET_APP_ICON
        self.page.title = settings.FLET_APP_NAME
        
        self.page.theme_mode = ft.ThemeMode.LIGHT
        self.page.padding = 0
        self.page.spacing = 0

        # 1. NUEVA FORMA DE SPLASH (Usando overlay)
        self.splash_container = ft.Container(
            content=ft.Column(
                [
                    ft.Image(src="favicon.png", width=180, height=180, fit=ft.ImageFit.CONTAIN),
                    ft.Container(height=20),
                    ft.ProgressRing(width=40, color="#6750A4"),
                    ft.Text("Cargando base de datos...", size=18, weight="bold", color="#6750A4")
                ],
                alignment=ft.MainAxisAlignment.CENTER,
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            alignment=ft.alignment.center,
            bgcolor=ft.colors.WHITE,
            expand=True,
            visible=True # Lo hacemos visible al inicio
        )
        
        self.page.overlay.append(self.splash_container)
        self.page.update()

        try:
            # 2. CARGA DE VISTAS
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

            time.sleep(1) # Tiempo para que el usuario vea el logo

        except Exception as e:
            print("--- ERROR AL INICIAR LA APP ---")
            traceback.print_exc()
            self.splash_container.content.controls.append(
                ft.Text(f"Error: {str(e)}", color=ft.colors.RED_700)
            )
            self.page.update()
            return

        # 3. QUITAR SPLASH CORRECTAMENTE
        self.splash_container.visible = False
        self.page.update()

    def _setup_theme(self):
        self.page.theme = ft.Theme(
            color_scheme=ft.ColorScheme(primary="#6750A4"),
            use_material3=True,
        )

    def _create_layout(self):
        self.content_area = ft.Container(expand=True, padding=20, bgcolor=ft.colors.WHITE)

        # RAIL (Desktop)
        self.navigation_rail = ft.NavigationRail(
            selected_index=0,
            extended=True,
            label_type=ft.NavigationRailLabelType.ALL,
            destinations=[
                ft.NavigationRailDestination(icon=ft.icons.INVENTORY, label="Inventario"),
                ft.NavigationRailDestination(icon=ft.icons.FACT_CHECK, label="Validación"),
                ft.NavigationRailDestination(icon=ft.icons.STORAGE, label="Stock"),
                ft.NavigationRailDestination(icon=ft.icons.HISTORY, label="Historial"),
                ft.NavigationRailDestination(icon=ft.icons.SETTINGS, label="Configuración"),
            ],
            on_change=self._on_navigation_change,
        )

        # BARRA (Móvil) - Corregido a NavigationBarDestination
        self.navigation_bar = ft.NavigationBar(
            destinations=[
                ft.NavigationBarDestination(icon=ft.icons.INVENTORY, label="Inventario"),
                ft.NavigationBarDestination(icon=ft.icons.FACT_CHECK, label="Validación"),
                ft.NavigationBarDestination(icon=ft.icons.STORAGE, label="Stock"),
                ft.NavigationBarDestination(icon=ft.icons.HISTORY, label="Historial"),
                ft.NavigationBarDestination(icon=ft.icons.SETTINGS, label="Config"),
            ],
            on_change=self._on_navigation_change,
        )

        self._layout_row = ft.Row(
            [self.navigation_rail, self.content_area],
            expand=True,
            spacing=0,
        )
        self.page.add(self._layout_row)

    def _handle_resize(self):
        def on_resize(e):
            if self.page.width < 700:
                self.navigation_rail.visible = False
                self._layout_row.controls = [self.content_area]
                self.page.navigation_bar = self.navigation_bar
            else:
                self.navigation_rail.visible = True
                self._layout_row.controls = [self.navigation_rail, self.content_area]
                self.page.navigation_bar = None
            self.page.update()
        self.page.on_resized = on_resize
        on_resize(None)

    def _on_navigation_change(self, e):
        self._show_view(int(e.control.selected_index))

    def _show_view(self, index: int):
        if self.current_view: self.current_view.visible = False
        view = self.views[index]
        self.content_area.content = view
        view.visible = True
        self.current_view = view
        self.navigation_rail.selected_index = index
        if self.page.navigation_bar: self.page.navigation_bar.selected_index = index
        self.page.update()

def _per_page_main(page: ft.Page):
    app = ControlEntradasSalidasApp()
    app.main(page)

if __name__ == "__main__":
    ft.app(
        target=_per_page_main,
        assets_dir=os.path.join(os.path.dirname(__file__), "assets"),
        view=ft.AppView.WEB_BROWSER
    )