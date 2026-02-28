import flet as ft
import traceback
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
        self.fcm_handler = None

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
        self.page.theme = ft.Theme(
            color_scheme_seed=ft.Colors.DEEP_PURPLE_700, 
            visual_density=ft.VisualDensity.COMFORTABLE,
            use_material3=True,
        )
        self.page.bgcolor = ft.Colors.SURFACE_CONTAINER_HIGHEST

    async def _handle_fcm_token(self, e):
        """Manejador de token que sincroniza con Supabase"""
        token_dispositivo = e.token
        print(f"🎫 Token generado: {token_dispositivo[:15]}...")
        
        try:
            # Importación local para evitar cargar la librería si no es necesario
            from supabase import create_client
            
            # Inicializamos cliente
            supabase = create_client(
                self.settings.SUPABASE_URL, 
                self.settings.SUPABASE_KEY
            )
            
            # Sincronizamos con la tabla fcm_tokens
            supabase.table("fcm_tokens").upsert({
                "token": token_dispositivo,
                "platform": "android",
                "app_name": self.settings.FLET_APP_NAME
            }).execute()
            
            print("🚀 Sincronización con Supabase exitosa.")
        except Exception as ex:
            print(f"❌ Error de registro en DB: {ex}")

    async def _setup_notifications(self):
        """Configura el handler de FCM y solicita permisos en Android"""
        try:
            # El módulo flet_fcm solo existirá dentro del APK generado
            import flet_fcm as fcm 

            # Inicializamos el componente con el manejador de la clase
            self.fcm_handler = fcm.Fcm(on_token=self._handle_fcm_token)
            
            # Agregamos al overlay para que esté activo en toda la app
            self.page.overlay.append(self.fcm_handler)
            self.page.update()
            
            # SOLICITUD DE PERMISO (Vital para Android 13+)
            print("🔔 Solicitando permiso de notificaciones...")
            self.fcm_handler.request_permission()
            
            print("✅ Sistema de notificaciones inicializado.")
            
        except ImportError:
            print("⚠️ FCM no disponible: Entorno de desarrollo local detectado.")
        except Exception as e:
            print(f"❌ Error inesperado en FCM: {e}")

    def _create_layout(self):
        # Área de contenido
        self.content_area = ft.Container(
            expand=True, 
            padding=0, 
            bgcolor=ft.Colors.WHITE,
            border_radius=ft.border_radius.only(top_left=20) if self.page.width >= 700 else 0
        )

        # BARRA LATERAL (Desktop/Tablet)
        self.navigation_rail = ft.NavigationRail(
            selected_index=0,
            extended=False,
            label_type=ft.NavigationRailLabelType.ALL,
            min_width=100,
            bgcolor=ft.Colors.DEEP_PURPLE_50,
            destinations=[
                ft.NavigationRailDestination(icon="inventory_2_outlined", selected_icon="inventory_2", label="Inventario"),
                ft.NavigationRailDestination(icon="fact_check_outlined", selected_icon="fact_check", label="Validación"),
                ft.NavigationRailDestination(icon="storage_outlined", selected_icon="storage", label="Stock"),
                ft.NavigationRailDestination(icon="history_outlined", selected_icon="history", label="Historial"),
                ft.NavigationRailDestination(icon="settings_outlined", selected_icon="settings", label="Ajustes"),
            ],
            on_change=self._on_navigation_change,
        )

        # BARRA INFERIOR (Mobile)
        self.navigation_bar = ft.NavigationBar(
            visible=False,
            bgcolor=ft.Colors.DEEP_PURPLE_50,
            destinations=[
                ft.NavigationBarDestination(icon="inventory_2_outlined", label="Inventario"),
                ft.NavigationBarDestination(icon="fact_check_outlined", label="Validar"),
                ft.NavigationBarDestination(icon="storage_outlined", label="Stock"),
                ft.NavigationBarDestination(icon="history_outlined", label="Historial"),
                ft.NavigationBarDestination(icon="settings_outlined", label="Ajustes"),
            ],
            on_change=self._on_navigation_change,
        )

        # DISEÑO PRINCIPAL CON SAFE AREA
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
    
    # Pantalla de Carga Inicial
    status_log = ft.Text("Verificando sistema...", color="grey")
    loading_container = ft.Container(
        content=ft.Column([
            ft.ProgressRing(color=ft.Colors.DEEP_PURPLE_700),
            ft.Text("Lycoris Control", size=22, weight="bold"),
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
        
        status_log.value = "Cargando Módulos..."
        page.update()
        from usr.views import InventarioView, ValidacionView, StockView, ConfiguracionView, HistorialFacturasView
        
        vistas = {
            0: InventarioView(),
            1: ValidacionView(),
            2: StockView(),
            3: HistorialFacturasView(),
            4: ConfiguracionView(),
        }
        
        app_instance = ControlEntradasSalidasApp()
        await app_instance.arrancar_interfaz(page, settings, vistas)
        
    except Exception as e:
        page.clean()
        error_stack = traceback.format_exc()
        page.add(
            ft.SafeArea(ft.Container(
                content=ft.Column([
                    ft.Icon(name="error_outline", color="red", size=60),
                    ft.Text("ERROR CRÍTICO", size=24, weight="bold"),
                    ft.Text(f"{e}", color="red", weight="bold"),
                    ft.Divider(),
                    ft.Text("Detalles técnicos:", size=12, color="grey"),
                    ft.Text(error_stack, size=10, font_family="monospace")
                ], scroll=ft.ScrollMode.ALWAYS), padding=20
            ))
        )
        page.update()

if __name__ == "__main__":
    ft.app(target=main)