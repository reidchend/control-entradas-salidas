import flet as ft
import traceback
import time

# --- 1. TU CLASE ORIGINAL DE INTERFAZ ---
# Nota: Le quitamos las importaciones pesadas. Solo maneja el diseño.
class ControlEntradasSalidasApp:
    def __init__(self):
        self.page = None
        self.navigation_rail = None
        self.navigation_bar = None
        self.content_area = None
        self.current_view = None
        self.views = None
        self._layout_row = None
        self.settings = None

    def arrancar_interfaz(self, page: ft.Page, settings, vistas_cargadas):
        self.page = page
        self.settings = settings
        self.views = vistas_cargadas
        
        # Limpiamos la pantalla de carga del Detective
        self.page.clean()

        # Configuraciones iniciales
        try:
            self.page.window_icon = self.settings.FLET_APP_ICON
            self.page.title = self.settings.FLET_APP_NAME
        except:
            pass
            
        self.page.theme_mode = ft.ThemeMode.LIGHT
        self.page.padding = 0
        self.page.spacing = 0

        self._setup_theme()
        self._create_layout()
        self._show_view(0)
        self._handle_resize()
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


# --- 2. EL MOTOR SEGURO (Tu Código Detective Mejorado) ---
def main(page: ft.Page):
    page.theme_mode = ft.ThemeMode.LIGHT
    page.scroll = ft.ScrollMode.ADAPTIVE
    
    # ¡PINTAR INMEDIATAMENTE PARA EVITAR PANTALLA NEGRA!
    loading_container = ft.Container(
        content=ft.Column([
            ft.ProgressRing(),
            ft.Text("Iniciando Lycoris Control...", size=20, weight="bold"),
            status_log := ft.Text("Verificando entorno...", color="grey")
        ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),
        alignment=ft.alignment.center,
        expand=True
    )
    page.add(loading_container)
    page.update()

    try:
        # PASO 1: Configuraciones
        status_log.value = "Cargando Pydantic y Config..."
        page.update()
        from config.config import get_settings
        settings = get_settings()
        
        # PASO 2: Vistas (Base de datos)
        status_log.value = "Conectando Base de Datos y Vistas..."
        page.update()
        from app.views import InventarioView, ValidacionView, StockView, ConfiguracionView, HistorialFacturasView
        
        vistas = {
            0: InventarioView(),
            1: ValidacionView(),
            2: StockView(),
            3: HistorialFacturasView(),
            4: ConfiguracionView(),
        }
        
        # PASO 3: Arrancar la App
        status_log.value = "Iniciando Interfaz Principal..."
        page.update()
        time.sleep(0.3) # Pequeña pausa para que se vea fluido
        
        # Invocamos la clase
        app_instance = ControlEntradasSalidasApp()
        app_instance.arrancar_interfaz(page, settings, vistas)
        
    except Exception as e:
        # SI ALGO FALLA, NUNCA SE QUEDARÁ EN NEGRO. VERÁS ESTO:
        page.clean()
        error_stack = traceback.format_exc()
        
        page.add(
            ft.Container(
                content=ft.Column([
                    ft.Icon(name="error_outline", color="red", size=60),
                    ft.Text("SE DETECTÓ UN ERROR", size=24, weight="bold", color="red"),
                    ft.Divider(),
                    ft.Text("Detalle del error:", weight="bold"),
                    ft.Container(
                        content=ft.Text(f"{e}", color="red", selectable=True),
                        bgcolor="#ffeeee", padding=10, border_radius=5
                    ),
                    ft.Text("Traceback:", weight="bold"),
                    ft.Container(
                        content=ft.Text(error_stack, size=11, font_family="monospace", selectable=True),
                        bgcolor="#f4f4f4", padding=10, border_radius=5
                    ),
                    ft.ElevatedButton("Reintentar", on_click=lambda _: page.update())
                ], spacing=15, scroll=ft.ScrollMode.ALWAYS),
                padding=20
            )
        )
        page.update()

# Punto de entrada estricto
if __name__ == "__main__":
    ft.app(target=main)