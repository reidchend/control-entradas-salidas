import flet as ft
import traceback
import time
import asyncio

# --- 1. CLASE DE INTERFAZ MODIFICADA ---
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

    async def arrancar_interfaz(self, page: ft.Page, settings, vistas_cargadas):
        self.page = page
        self.settings = settings
        self.views = vistas_cargadas
        
        self.page.clean()

        # Configuraciones iniciales
        try:
            self.page.window_icon = self.settings.FLET_APP_ICON
            self.page.title = self.settings.FLET_APP_NAME
        except:
            pass
            
        self.page.theme_mode = ft.ThemeMode.LIGHT
        # Quitamos el padding de la página porque usaremos SafeArea
        self.page.padding = 0
        self.page.spacing = 0
        self.page.expand = True

        self._setup_theme()
        
        # --- SOLICITUD DE PERMISOS Y NOTIFICACIONES ---
        await self._setup_notifications() 
        
        self._create_layout()
        self._show_view(0)
        self._handle_resize()
        self.page.update()

    def _setup_theme(self):
        # Usando el color morado fuerte que pediste anteriormente
        self.page.theme = ft.Theme(
            color_scheme_seed=ft.Colors.DEEP_PURPLE_700, 
            visual_density=ft.VisualDensity.COMFORTABLE,
            use_material3=True,
        )
        self.page.bgcolor = ft.Colors.SURFACE_CONTAINER_HIGHEST

    async def _setup_notifications(self):
        # Manejador de mensajes recibidos
        def on_fcm_message(e):
            self.page.show_snack_bar(
                ft.SnackBar(
                    content=ft.Row([
                        ft.Icon(ft.Icons.NOTIFICATION_IMPORTANT, color="white"),
                        ft.Text(f"Aviso Stock: {e.data}")
                    ]),
                    bgcolor=ft.Colors.DEEP_PURPLE_700
                )
            )

        self.page.on_fcm_message = on_fcm_message

        try:
            # MÉTODO COMPATIBLE 0.28.x:
            # Intentamos pedir el permiso de forma directa. 
            # Si el método no existe, lo saltamos silenciosamente para evitar el cierre de la app.
            if hasattr(self.page, "request_permission"):
                # Algunos entornos de Flet prefieren la versión sincrónica que internamente es async
                await self.page.request_permission_async(ft.PermissionType.REMOTE_NOTIFICATIONS)
            
            # Suscripción a tópicos
            # En 0.28.3, subscribe suele ser un método directo de page si está compilado para móvil
            if hasattr(self.page, "subscribe"):
                # Intentamos la suscripción
                self.page.subscribe("stock_updates")
                print("Suscripción exitosa a stock_updates")
                
        except Exception as ex:
            print(f"Aviso: FCM no configurado en este entorno (Posiblemente Web/PC): {ex}")

    def _create_layout(self):
        # Área de contenido
        self.content_area = ft.Container(
            expand=True, 
            padding=0, 
            bgcolor=ft.Colors.WHITE,
            border_radius=ft.border_radius.only(top_left=20) if self.page.width >= 700 else 0
        )

        # BARRA LATERAL
        self.navigation_rail = ft.NavigationRail(
            selected_index=0,
            extended=False,
            label_type=ft.NavigationRailLabelType.ALL,
            min_width=100,
            bgcolor=ft.Colors.DEEP_PURPLE_50, # Un tono más claro para el fondo
            destinations=[
                ft.NavigationRailDestination(icon="inventory_2_outlined", selected_icon="inventory_2", label="Inventario"),
                ft.NavigationRailDestination(icon="fact_check_outlined", selected_icon="fact_check", label="Validación"),
                ft.NavigationRailDestination(icon="storage_outlined", selected_icon="storage", label="Stock"),
                ft.NavigationRailDestination(icon="history_outlined", selected_icon="history", label="Historial"),
                ft.NavigationRailDestination(icon="settings_outlined", selected_icon="settings", label="Ajustes"),
            ],
            on_change=self._on_navigation_change,
        )

        # BARRA INFERIOR
        self.navigation_bar = ft.NavigationBar(
            visible=False,
            bgcolor=ft.Colors.DEEP_PURPLE_50,
            destinations=[
                ft.NavigationBarDestination(icon="inventory_2_outlined", label="Inventario"),
                ft.NavigationBarDestination(icon="fact_check_outlined", label="Validación"),
                ft.NavigationBarDestination(icon="storage_outlined", label="Stock"),
                ft.NavigationBarDestination(icon="history_outlined", label="Historial"),
                ft.NavigationBarDestination(icon="settings_outlined", label="Config"),
            ],
            on_change=self._on_navigation_change,
        )

        # --- MEJORA: SAFE AREA ---
        # El SafeArea protege el contenido de la barra de estado y el notch
        self._layout_row = ft.SafeArea(
            content=ft.Row(
                [self.navigation_rail, self.content_area],
                expand=True,
                spacing=0,
            ),
            expand=True,
            minimum_padding=ft.padding.only(top=10) # Espacio extra por seguridad
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


# --- 2. MOTOR DE CARGA ASÍNCRONO ---
async def main(page: ft.Page):
    page.expand = True
    
    # Pantalla de Carga
    status_log = ft.Text("Verificando entorno...", color="grey")
    loading_container = ft.Container(
        content=ft.Column([
            ft.ProgressRing(color=ft.Colors.DEEP_PURPLE_700),
            ft.Text("Iniciando Control...", size=20, weight="bold"),
            status_log
        ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),
        alignment=ft.alignment.center,
        expand=True
    )
    page.add(loading_container)
    page.update()

    try:
        status_log.value = "Cargando Configuración..."
        page.update()
        from config.config import get_settings
        settings = get_settings()
        
        status_log.value = "Cargando Vistas..."
        page.update()
        from app.views import InventarioView, ValidacionView, StockView, ConfiguracionView, HistorialFacturasView
        
        vistas = {
            0: InventarioView(),
            1: ValidacionView(),
            2: StockView(),
            3: HistorialFacturasView(),
            4: ConfiguracionView(),
        }
        
        app_instance = ControlEntradasSalidasApp()
        # Llamada asíncrona al arranque
        await app_instance.arrancar_interfaz(page, settings, vistas)
        
    except Exception as e:
        page.clean()
        error_stack = traceback.format_exc()
        page.add(
            ft.SafeArea(ft.Container(
                content=ft.Column([
                    ft.Icon(name="error_outline", color="red", size=60),
                    ft.Text("ERROR DE CARGA", size=24, weight="bold"),
                    ft.Text(f"{e}", color="red"),
                    ft.Text(error_stack, size=10, font_family="monospace")
                ], scroll=ft.ScrollMode.ALWAYS), padding=20
            ))
        )
        page.update()

if __name__ == "__main__":
    # Ejecución asíncrona
    ft.app(target=main)