import flet as ft
import os
import time
import traceback

# Intentamos importar las configuraciones con seguridad
try:
    from config.config import get_settings
    settings = get_settings()
except Exception as e:
    # Si falla la configuración, creamos un objeto dummy para que no rompa el resto
    class DummySettings:
        FLET_APP_NAME = "Error de Configuración"
        FLET_APP_ICON = None
    settings = DummySettings()
    CONFIG_ERROR = str(e)
else:
    CONFIG_ERROR = None

class ControlEntradasSalidasApp:
    def __init__(self):
        self.page = None
        self.navigation_rail = None
        self.navigation_bar = None
        self.content_area = None
        self.current_view = None
        self.views = None
        self.splash_container = None

    def main(self, page: ft.Page):
        self.page = page
        self.page.window_icon = settings.FLET_APP_ICON
        self.page.title = settings.FLET_APP_NAME
        
        self.page.theme_mode = ft.ThemeMode.LIGHT
        self.page.padding = 0
        self.page.spacing = 0

        # 1. SPLASH SCREEN (Overlay)
        self.splash_container = ft.Container(
            content=ft.Column(
                [
                    ft.Image(src="favicon.png", width=180, height=180, fit=ft.ImageFit.CONTAIN),
                    ft.Container(height=20),
                    ft.ProgressRing(width=40, color="#6750A4"),
                    ft.Text("Iniciando sistema...", size=18, weight="bold", color="#6750A4"),
                    # Area para mensajes de error (vacía al inicio)
                    self.error_text := ft.Text("", color=ft.colors.RED_700, size=12, selectable=True)
                ],
                alignment=ft.MainAxisAlignment.CENTER,
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                scroll=ft.ScrollMode.ADAPTIVE # Por si el error es largo
            ),
            alignment=ft.alignment.center,
            bgcolor=ft.colors.WHITE,
            expand=True,
            visible=True
        )
        
        self.page.overlay.append(self.splash_container)
        self.page.update()

        # Si hubo un error en las importaciones iniciales (Config)
        if CONFIG_ERROR:
            self._handle_critical_error(f"Error en Config/Dotenv: {CONFIG_ERROR}")
            return

        try:
            # 2. CARGA DE VISTAS (Punto crítico de librerías como SQLAlchemy)
            from app.views import InventarioView, ValidacionView, StockView, ConfiguracionView, HistorialFacturasView
            
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

            time.sleep(1) # Feedback visual

        except Exception as e:
            error_detail = traceback.format_exc()
            self._handle_critical_error(error_detail)
            return

        # 3. QUITAR SPLASH SI TODO OK
        self.splash_container.visible = False
        self.page.update()

    def _handle_critical_error(self, error_message):
        print(f"--- ERROR CRÍTICO ---\n{error_message}")
        # Detenemos el anillo de progreso y mostramos el error
        self.splash_container.content.controls[2].visible = False # Oculta ProgressRing
        self.splash_container.content.controls[3].value = "Error al iniciar aplicación"
        self.error_text.value = error_message
        self.page.update()

    def _setup_theme(self):
        self.page.theme = ft.Theme(
            color_scheme=ft.ColorScheme(primary="#6750A4"),
            use_material3=True,
        )

    def _create_layout(self):
        self.content_area = ft.Container(expand=True, padding=20, bgcolor=ft.colors.WHITE)

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
        assets_dir=os.path.join(os.path.dirname(__file__), "assets")
    )