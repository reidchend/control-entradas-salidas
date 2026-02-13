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
        self.error_text = None
        self._layout_row = None

    def main(self, page: ft.Page):
        self.page = page
        
        # Configuraciones iniciales básicas
        try:
            self.page.window_icon = settings.FLET_APP_ICON
            self.page.title = settings.FLET_APP_NAME
        except:
            pass
            
        self.page.theme_mode = ft.ThemeMode.LIGHT
        self.page.padding = 0
        self.page.spacing = 0

        # CORRECCIÓN DE SINTAXIS
        self.error_text = ft.Text("", color=ft.colors.RED_700, size=12, selectable=True)

        # 1. SPLASH SCREEN
        self.splash_container = ft.Container(
            content=ft.Column(
                [
                    ft.Container(height=20),
                    ft.ProgressRing(width=40, color="#6750A4"),
                    ft.Text("Iniciando sistema...", size=18, weight="bold", color="#6750A4"),
                    self.error_text
                ],
                alignment=ft.MainAxisAlignment.CENTER,
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                scroll=ft.ScrollMode.ADAPTIVE 
            ),
            alignment=ft.alignment.center,
            bgcolor=ft.colors.WHITE,
            expand=True,
            visible=True
        )
        
        self.page.add(self.splash_container)
        self.page.update()

        if CONFIG_ERROR:
            self._handle_critical_error(f"Error en Config/Dotenv: {CONFIG_ERROR}")
            return

        try:
            # 2. CARGA DE VISTAS
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

            time.sleep(0.5) 

            # 3. QUITAR SPLASH SI TODO OK
            self.splash_container.visible = False
            self.page.update()

        except Exception as e:
            error_detail = traceback.format_exc()
            self._handle_critical_error(error_detail)

    def _handle_critical_error(self, error_message):
        print(f"--- ERROR CRÍTICO ---\n{error_message}")
        if self.splash_container:
            # CORRECCIÓN: Evitamos usar ft.icons aquí también por seguridad
            self.splash_container.content.controls[1].visible = False 
            self.splash_container.content.controls[2].value = "Error al iniciar"
            self.error_text.value = error_message
            self.page.update()

    def _setup_theme(self):
        self.page.theme = ft.Theme(
            color_scheme=ft.ColorScheme(primary="#6750A4"),
            use_material3=True,
        )

    def _create_layout(self):
        self.content_area = ft.Container(expand=True, padding=20, bgcolor=ft.colors.WHITE)

        # CORRECCIÓN: Iconos como Strings para evitar error de atributo en Android
        self.navigation_rail = ft.NavigationRail(
            selected_index=0,
            extended=True,
            label_type=ft.NavigationRailLabelType.ALL,
            destinations=[
                ft.NavigationRailDestination(icon="inventory", label="Inventario"),
                ft.NavigationRailDestination(icon="fact_check", label="Validación"),
                ft.NavigationRailDestination(icon="storage", label="Stock"),
                ft.NavigationRailDestination(icon="history", label="Historial"),
                ft.NavigationRailDestination(icon="settings", label="Configuración"),
            ],
            on_change=self._on_navigation_change,
        )

        self.navigation_bar = ft.NavigationBar(
            destinations=[
                ft.NavigationDestination(icon="inventory", label="Inventario"),
                ft.NavigationDestination(icon="fact_check", label="Validación"),
                ft.NavigationDestination(icon="storage", label="Stock"),
                ft.NavigationDestination(icon="history", label="Historial"),
                ft.NavigationDestination(icon="settings", label="Config"),
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
                if self.navigation_rail: self.navigation_rail.visible = False
                self._layout_row.controls = [self.content_area]
                self.page.navigation_bar = self.navigation_bar
            else:
                if self.navigation_rail: self.navigation_rail.visible = True
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

# Ejecución
app_instance = ControlEntradasSalidasApp()
if __name__ == "__main__":
    ft.app(target=app_instance.main)