import flet as ft
import traceback
import time

# --- 1. TU CLASE ORIGINAL DE INTERFAZ ---
# Restaurado exactamente como lo tenías para compatibilidad con Flet 0.28.3
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
        self.page.expand = True
        self.page.vertical_alignment = ft.MainAxisAlignment.START

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
        # Área de contenido
        self.content_area = ft.Container(
            expand=True, 
            padding=0, 
            bgcolor=ft.Colors.WHITE,
            border_radius=ft.border_radius.only(top_left=20) if self.page.width >= 700 else 0
        )

        # BARRA LATERAL (PC/Tablet)
        self.navigation_rail = ft.NavigationRail(
            selected_index=0,
            extended=False,
            label_type=ft.NavigationRailLabelType.ALL,
            min_width=100,
            bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
            destinations=[
                ft.NavigationRailDestination(icon="inventory_2_outlined", selected_icon="inventory_2", label="Inventario"),
                ft.NavigationRailDestination(icon="fact_check_outlined", selected_icon="fact_check", label="Validación"),
                ft.NavigationRailDestination(icon="storage_outlined", selected_icon="storage", label="Stock"),
                ft.NavigationRailDestination(icon="history_outlined", selected_icon="history", label="Historial"),
                ft.NavigationRailDestination(icon="settings_outlined", selected_icon="settings", label="Ajustes"),
            ],
            on_change=self._on_navigation_change,
        )

        # BARRA INFERIOR (Móvil) - Restaurado NavigationBarDestination
        self.navigation_bar = ft.NavigationBar(
            visible=False,
            label_behavior=ft.NavigationBarLabelBehavior.ALWAYS_HIDE,
            destinations=[
                ft.NavigationBarDestination(icon="inventory_2_outlined", selected_icon="inventory_2", label="Inventario"),
                ft.NavigationBarDestination(icon="fact_check_outlined", selected_icon="fact_check", label="Validación"),
                ft.NavigationBarDestination(icon="storage_outlined", selected_icon="storage", label="Stock"),
                ft.NavigationBarDestination(icon="history_outlined", selected_icon="history", label="Historial"),
                ft.NavigationBarDestination(icon="settings_outlined", selected_icon="settings", label="Config"),
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
                self.page.navigation_bar = self.navigation_bar
                self.page.navigation_bar.visible = True
                self.content_area.border_radius = 0
            else:
                self.navigation_rail.visible = True
                self.page.navigation_bar = None
                self.content_area.border_radius = ft.border_radius.only(top_left=20)
            
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


# --- 2. EL MOTOR DE CARGA ---
def main(page: ft.Page):
    page.theme_mode = ft.ThemeMode.LIGHT
    page.expand = True
    
    # UI de carga inicial
    status_log = ft.Text("Verificando entorno...", color="grey")
    loading_container = ft.Container(
        content=ft.Column([
            ft.ProgressRing(),
            ft.Text("Iniciando Lycoris Control...", size=20, weight="bold"),
            status_log
        ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),
        alignment=ft.alignment.center,
        expand=True
    )
    page.add(loading_container)
    page.update()

    try:
        # PASO 1: Configuraciones
        status_log.value = "Cargando Configuración..."
        page.update()
        from config.config import get_settings
        settings = get_settings()
        
        # PASO 2: Vistas
        status_log.value = "Cargando Vistas y Base de Datos..."
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
        time.sleep(0.3)
        
        app_instance = ControlEntradasSalidasApp()
        app_instance.arrancar_interfaz(page, settings, vistas)
        
    except Exception as e:
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

if __name__ == "__main__":
    ft.app(target=main)