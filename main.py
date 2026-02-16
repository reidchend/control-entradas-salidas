import sys
import traceback
import os
import time
import flet as ft

# Intentamos importar las configuraciones
try:
    from config.config import get_settings
    settings = get_settings()
    CONFIG_ERROR = None
except Exception as e:
    # Objeto dummy para no romper el inicio si falla config
    class DummySettings:
        FLET_APP_NAME = "Error de Configuración"
        FLET_APP_ICON = None
    settings = DummySettings()
    CONFIG_ERROR = str(e)


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
        self.settings = None

    def arrancar_interfaz(self, page: ft.Page, settings, vistas_cargadas):
        self.page = page
        self.settings = settings
        self.views = vistas_cargadas
        
        # Limpiamos la pantalla de carga
        self.page.clean()

        # Configuración visual
        try:
            self.page.window_icon = self.settings.FLET_APP_ICON
            self.page.title = self.settings.FLET_APP_NAME
        except:
            pass
            
        self.page.theme_mode = ft.ThemeMode.LIGHT
        
        # IMPORTANTE: Quitamos padding global para que el SafeArea controle los bordes
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
            color_scheme=ft.ColorScheme(primary="#6750A4"),
            use_material3=True,
        )

    def _create_layout(self):
        # Contenedor principal del contenido
        self.content_area = ft.Container(
            expand=True, 
            padding=0, 
            bgcolor=ft.Colors.WHITE,
            border_radius=ft.border_radius.only(top_left=20) if self.page.width >= 700 else 0
        )

        # Barra Lateral (Escritorio)
        self.navigation_rail = ft.NavigationRail(
            selected_index=0,
            extended=False,
            label_type=ft.NavigationRailLabelType.ALL,
            destinations=[
                ft.NavigationRailDestination(icon="inventory_2_outlined", selected_icon="inventory_2", label="Inventario"),
                ft.NavigationRailDestination(icon="fact_check_outlined", selected_icon="fact_check", label="Validación"),
                ft.NavigationRailDestination(icon="storage_outlined", selected_icon="storage", label="Stock"),
                ft.NavigationRailDestination(icon="history_outlined", selected_icon="history", label="Historial"),
                ft.NavigationRailDestination(icon="settings_outlined", selected_icon="settings", label="Config"),
            ],
            on_change=self._on_navigation_change,
        )

        # Barra Inferior (Móvil)
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

        # Layout principal
        self._layout_row = ft.Row(
            [self.navigation_rail, self.content_area],
            expand=True,
            spacing=0,
        )
        
        # --- SOLUCIÓN MAESTRA AL PROBLEMA DE LA BARRA DE ESTADO ---
        # Envolvemos todo el layout en un SafeArea.
        # Esto añade automáticamente el padding necesario arriba (notch) y abajo (gestos).
        self.page.add(
            ft.SafeArea(
                content=self._layout_row,
                expand=True,
            )
        )

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


# --- PUNTO DE ENTRADA CON SPLASH SCREEN ---
def main(page: ft.Page):
    page.theme_mode = ft.ThemeMode.LIGHT
    page.scroll = None
    page.expand = True
    page.padding = 0  # Quitamos padding manual, SafeArea se encarga

    # Pantalla de carga (Splash)
    # También le ponemos SafeArea por si el splash tiene texto muy arriba
    status_log = ft.Text("Verificando entorno...", color="grey")
    
    loading_content = ft.Column([
        ft.ProgressRing(),
        ft.Container(height=10),
        ft.Text("Iniciando Lycoris Control...", size=20, weight="bold"),
        status_log
    ], horizontal_alignment=ft.CrossAxisAlignment.CENTER)

    loading_container = ft.Container(
        content=ft.SafeArea( # SafeArea para el splash también
            ft.Container(
                content=loading_content,
                alignment=ft.alignment.center
            ),
            expand=True
        ),
        alignment=ft.alignment.center,
        expand=True,
        bgcolor=ft.Colors.WHITE
    )
    
    page.add(loading_container)
    page.update()

    try:
        # Carga progresiva de módulos
        status_log.value = "Cargando configuraciones..."
        page.update()
        from config.config import get_settings
        settings = get_settings()
        
        status_log.value = "Conectando módulos..."
        page.update()
        from app.views import InventarioView, ValidacionView, StockView, ConfiguracionView, HistorialFacturasView
        
        vistas = {
            0: InventarioView(),
            1: ValidacionView(),
            2: StockView(),
            3: HistorialFacturasView(),
            4: ConfiguracionView(),
        }
        
        status_log.value = "Iniciando interfaz..."
        page.update()
        time.sleep(0.3)
        
        # Lanzar la app real
        app_instance = ControlEntradasSalidasApp()
        app_instance.arrancar_interfaz(page, settings, vistas)
        
    except Exception as e:
        page.clean()
        error_stack = traceback.format_exc()
        
        # Pantalla de error crítica (También con SafeArea para poder leerla bien)
        page.add(
            ft.SafeArea(
                ft.Container(
                    content=ft.Column([
                        ft.Icon(name="error_outline", color="red", size=60),
                        ft.Text("ERROR DE INICIO", size=24, weight="bold", color="red"),
                        ft.Divider(),
                        ft.Text("Detalle:", weight="bold"),
                        ft.Container(
                            content=ft.Text(f"{e}", color="red", selectable=True),
                            bgcolor="#ffeeee", padding=10, border_radius=5
                        ),
                        ft.Text("Traceback:", weight="bold"),
                        ft.Container(
                            content=ft.Text(error_stack, size=10, font_family="monospace", selectable=True),
                            bgcolor="#f4f4f4", padding=10, border_radius=5, expand=True
                        ),
                        ft.ElevatedButton("Reintentar", on_click=lambda _: page.update())
                    ], spacing=10),
                    padding=20,
                    expand=True
                ),
                expand=True
            )
        )
        page.update()

if __name__ == "__main__":
    ft.app(target=main)