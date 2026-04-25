import flet as ft
import traceback
import os
import ssl
import certifi
import glob
import warnings
import asyncio
import sys

# Deshabilitar warning de asyncio "Task was destroyed"
os.environ['PYTHONASYNCIODEBUG'] = '0'  # Deshabilitar debug de asyncio
warnings.filterwarnings("ignore", category=ResourceWarning)
warnings.filterwarnings("ignore", message=".*Task.*destroyed.*")

# Esto le dice a Python exactamente dónde encontrar los certificados
os.environ['SSL_CERT_FILE'] = certifi.where()


def resource_path(relative_path: str) -> str:
    """Obtiene ruta absoluta de recursos, compatible con PyInstaller y desarrollo."""
    # Si estamos en el .exe de PyInstaller
    if hasattr(sys, '_MEIPASS'):
        meipass = sys._MEIPASS
        path = os.path.join(meipass, relative_path)
        if os.path.exists(path):
            return path
        # En Windows, PyInstaller puede usar paths diferentes
        return os.path.join(os.path.dirname(sys.executable), relative_path)
    
    # En desarrollo, buscar desde el directorio del script
    base_dir = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(base_dir, relative_path)
    if os.path.exists(path):
        return path
    
    # Último fallback: directorio actual
    return os.path.abspath(relative_path)


def log_debug(msg):
    """Registra mensajes de debug con timestamp"""
    import time
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


def mostrar_error_critico(page: ft.Page, error_completo: str):
    """Pantalla de error profesional compatible con versiones 0.2x de Flet."""
    page.clean()
    page.bgcolor = "#1a0000"
    
    error_container = ft.Column(
        scroll=ft.ScrollMode.ALWAYS,
        expand=True,
        controls=[
            ft.Text("DETALLES TÉCNICOS:", weight=ft.FontWeight.BOLD, color=ft.Colors.RED_200),
            ft.Container(
                content=ft.Text(
                    error_completo,
                    size=11,
                    font_family="monospace",
                    color=ft.Colors.RED_100,
                ),
                padding=10,
                bgcolor="#330000",
                border_radius=5,
            ),
        ]
    )

    page.add(
        ft.Container(
            padding=20,
            content=ft.Column([
                ft.Icon(ft.Icons.REPORT_PROBLEM_ROUNDED, color=ft.Colors.RED_400, size=50),
                ft.Text("Error de Inicio", size=24, weight=ft.FontWeight.BOLD),
                ft.Text("La aplicación no pudo arrancar correctamente.", text_align=ft.TextAlign.CENTER),
                ft.Divider(color=ft.Colors.RED_900),
                ft.Container(content=error_container, height=300),
                ft.ElevatedButton(
                    "Copiar Error al Portapapeles",
                    icon=ft.Icons.COPY,
                    on_click=lambda _: page.set_clipboard(error_completo)
                ),
                ft.Container(height=10),
                ft.ElevatedButton(
                    "Reintentar Inicio",
                    bgcolor=ft.Colors.RED_700,
                    color=ft.Colors.WHITE,
                    on_click=lambda _: page.go("/") 
                )
            ], horizontal_alignment=ft.CrossAxisAlignment.CENTER)
        )
    )
    page.update()


class ControlEntradasSalidasApp:
    def __init__(self):
        # Type hints para que Pylance entienda el tipo de cada atributo
        self.page: ft.Page = None
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
        
        self.page.title = self.settings.FLET_APP_NAME
        self.page.theme_mode = ft.ThemeMode.DARK
        self.page.padding = 0
        self.page.spacing = 0
        self.page.expand = True

        self._setup_theme()
        self._create_layout()
        self._handle_responsive_layout(self.page.width)
        self._show_view(0)
        
        self.page.on_resized = self._on_page_resized
        self.page.update()

    def _setup_theme(self):
        if not self.page:
            return
        self.page.theme = ft.Theme(color_scheme_seed=ft.Colors.DEEP_PURPLE_700, visual_density=ft.VisualDensity.COMFORTABLE, use_material3=True)
        self.page.bgcolor = '#1A1A1A'
    
    def _toggle_theme(self, e=None):
        if not self.page:
            return

        is_dark = self.page.theme_mode != ft.ThemeMode.DARK
        self.page.theme_mode = ft.ThemeMode.DARK if is_dark else ft.ThemeMode.LIGHT
        self.page.bgcolor = '#1A1A1A' if is_dark else '#F5F5F5'

        if hasattr(self, 'content_area') and self.content_area:
            self.content_area.bgcolor = '#252525' if is_dark else '#FFFFFF'

        if hasattr(self, 'navigation_rail') and self.navigation_rail:
            self.navigation_rail.bgcolor = '#1E1E1E' if is_dark else '#F3E5F5'

        if hasattr(self, 'theme_toggle') and self.theme_toggle:
            self.theme_toggle.icon = ft.Icons.LIGHT_MODE if is_dark else ft.Icons.DARK_MODE
            self.theme_toggle.icon_color = ft.Colors.AMBER if is_dark else ft.Colors.BLUE_GREY_700
            self.theme_toggle.tooltip = "Modo Claro" if is_dark else "Modo Oscuro"

        if self.current_view and hasattr(self.current_view, 'on_theme_change'):
            self.current_view.on_theme_change()

        self.page.update()

    def _create_layout(self):
        self.content_area = ft.Container(expand=True, padding=0, bgcolor='#252525', border_radius=0)

        self.theme_toggle = ft.IconButton(icon=ft.Icons.LIGHT_MODE, tooltip="Modo Claro", on_click=self._toggle_theme, icon_color=ft.Colors.AMBER)

        self.navigation_rail = ft.NavigationRail(
            selected_index=0, extended=False, label_type=ft.NavigationRailLabelType.ALL, min_width=100, bgcolor='#1E1E1E', 
            leading=self.theme_toggle,
            destinations=[
                ft.NavigationRailDestination(icon=ft.Icons.SHOPPING_CART_OUTLINED, selected_icon=ft.Icons.SHOPPING_CART, label="Inventario"),
                ft.NavigationRailDestination(icon=ft.Icons.CHECKLIST_OUTLINED, selected_icon=ft.Icons.CHECKLIST, label="Validación"),
                ft.NavigationRailDestination(icon=ft.Icons.WAREHOUSE_OUTLINED, selected_icon=ft.Icons.WAREHOUSE, label="Stock"),
                ft.NavigationRailDestination(icon=ft.Icons.LOCAL_SHIPPING_OUTLINED, selected_icon=ft.Icons.LOCAL_SHIPPING, label="Requisiciones"),
                ft.NavigationRailDestination(icon=ft.Icons.HISTORY_OUTLINED, selected_icon=ft.Icons.HISTORY, label="Historial"),
                ft.NavigationRailDestination(icon=ft.Icons.SETTINGS_OUTLINED, selected_icon=ft.Icons.SETTINGS, label="Ajustes"),
            ], on_change=self._on_navigation_change,
        )

        self.navigation_bar = ft.NavigationBar(
            visible=False, bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
            destinations=[
                ft.NavigationBarDestination(icon=ft.Icons.SHOPPING_CART_OUTLINED, label="Inventario"),
                ft.NavigationBarDestination(icon=ft.Icons.CHECKLIST_OUTLINED, label="Validar"),
                ft.NavigationBarDestination(icon=ft.Icons.WAREHOUSE_OUTLINED, label="Stock"),
                ft.NavigationBarDestination(icon=ft.Icons.MORE_VERT, label="Más"),
            ], on_change=self._on_navigation_change,
        )

        self._layout_row = ft.SafeArea(content=ft.Row([self.navigation_rail, self.content_area], expand=True, spacing=0), expand=True)
        self.page.clean()
        self.page.padding = 5
        self.page.add(self._layout_row)

    def _on_page_resized(self, e):
        self._handle_responsive_layout(float(e.width))
        self.page.update()

    def _handle_responsive_layout(self, width):
        if width < 700:
            self.navigation_rail.visible = False
            self.page.navigation_bar = self.navigation_bar
            self.navigation_bar.visible = True
            self.content_area.border_radius = 0
        else:
            self.navigation_rail.visible = True
            self.page.navigation_bar = None
            self.navigation_bar.visible = False
            self.content_area.border_radius = ft.border_radius.only(top_left=20)

    def _on_navigation_change(self, e):
        if self.page is None:
            return
            
        index = int(e.control.selected_index)
        if isinstance(e.control, ft.NavigationBar) and index == 3:
            self._show_more_menu()
            return
            
        self.current_view_index = index
        self._show_view(index)

    def _show_more_menu(self):
        if self.page is None:
            return
            
        opciones = [("assignment", "Requisiciones", 3), ("history", "Historial", 4), ("settings", "Ajustes", 5)]
        
        is_dark = self.page.theme_mode == ft.ThemeMode.DARK
        theme_icon = ft.Icons.LIGHT_MODE if is_dark else ft.Icons.DARK_MODE
        theme_label = "Modo Claro" if is_dark else "Modo Oscuro"

        def on_toggle_theme(e):
            self.page.close(self.bottom_sheet)
            self._toggle_theme()

        def on_nav(e, idx):
            self.page.close(self.bottom_sheet)
            self._show_view(idx)

        menu_content = ft.Column(spacing=0, controls=[
            ft.Container(
                content=ft.Row([ft.Icon(theme_icon, size=24), ft.Text(theme_label, size=16)], spacing=15),
                padding=ft.padding.all(15),
                on_click=on_toggle_theme,
            ),
            ft.Divider(height=1, color='#3D3D3D'),
            *[
                ft.Container(
                    content=ft.Row([ft.Icon(icon, size=24), ft.Text(label, size=16)], spacing=15),
                    padding=ft.padding.all(15),
                    on_click=lambda e, i=idx: on_nav(e, i),
                )
                for icon, label, idx in opciones
            ]
        ])
        
        self.bottom_sheet = ft.BottomSheet(content=ft.Container(content=menu_content, padding=ft.padding.only(bottom=20)), open=True)
        self.page.open(self.bottom_sheet)
    
    def _show_view(self, index: int):
        if not self.views or index not in self.views: return
        view = self.views[index]
        
        if self.current_view: 
            self.current_view.visible = False
            
        self.content_area.content = view
        view.visible = True
        self.current_view = view
        self.current_view_index = index
        
        self.navigation_rail.selected_index = index
        if self.navigation_bar:
            if index < 3:
                self.navigation_bar.selected_index = index
            else:
                self.navigation_bar.selected_index = 3 
        
        # LOGICA RESTAURADA: Actualizar indicador de conexión si existe en la vista
        if hasattr(view, '_update_connection_indicator'):
            try:
                if hasattr(view, '_connection_indicator') and view._connection_indicator in self.page.controls:
                    view._update_connection_indicator()
            except:
                pass
        
        self.page.update()


async def main(page: ft.Page):
    # Identidad visual
    page.title = "Lycoris Control"
    
    # Debug - siempre mostrar
    icono_path = resource_path("assets/icono.ico")
    favicon_path = resource_path("assets/favicon.png")
    meipass = getattr(sys, '_MEIPASS', 'NO_PYINSTALLER')
    import io, sys
    sys.stdout = sys.__stdout__
    print(f"[DEBUG PyInstaller] _MEIPASS: {meipass}")
    print(f"[DEBUG] Icono path: {icono_path}")
    print(f"[DEBUG] Icono existe: {os.path.exists(icono_path)}")
    print(f"[DEBUG] Favicon path: {favicon_path}")
    print(f"[DEBUG] Favicon existe: {os.path.exists(favicon_path)}")
    
    page.window_icon = icono_path
    page.favicon = favicon_path
    page.assets_allow_override = True
    page.locale_configuration = ft.LocaleConfiguration(
        supported_locales=[ft.Locale("es")],
        current_locale=ft.Locale("es"),
    )
    
    # LOGICA RESTAURADA: Configuración regional del sistema operativo
    import locale
    try:
        locale.setlocale(locale.LC_ALL, 'es_ES.UTF-8')
    except:
        try:
            locale.setlocale(locale.LC_ALL, 'es_MX.UTF-8')
        except:
            try:
                locale.setlocale(locale.LC_ALL, 'spanish')
            except:
                pass

    try:
        page.bgcolor = "#121212"
        page.update()
        
        # LOGICA RESTAURADA: Determina el path según la plataforma
        import os
        from usr.database.conn import set_db_path, get_db_path
        
        # Intentar usar app_data_dir primero (Android tiene permisos)
        db_dir = None
        try:
            if hasattr(page, 'app_data_dir') and page.app_data_dir:
                db_dir = page.app_data_dir
        except:
            pass
        
        # Si no funciona, usar directorio actual (siempre escribible)
        if not db_dir:
            db_dir = "."
        
        page.session.set("_db_dir", db_dir)
        db_path = os.path.join(db_dir, "lycoris_local.db")
        
        # Inicializar BD
        from usr.database.local_replica import ensure_local_db
        
        try:
            set_db_path(db_path)
        except Exception as e:
            print(f"[WARN] Error set_db_path: {e}")
            # Intentar con directorio actual
            try:
                set_db_path("lycoris_local.db")
            except Exception as e2:
                print(f"[WARN] Error set_db_path fallback: {e2}")
        
        try:
            ensure_local_db()
        except Exception as e:
            print(f"[WARN] Error ensure_local_db: {e}")

        # LOGICA RESTAURADA: Interfaz de carga original
        logo = ft.Column([
            ft.Image(src="/icono.png", width=120, height=120, fit=ft.ImageFit.CONTAIN, error_content=ft.Text("Logo no encontrado", color=ft.Colors.RED)),
            ft.Text("Lycoris", size=32, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE),
            ft.Text("Control de Entradas y Salidas", size=16, color="#9E9E9E"),
        ], horizontal_alignment="center", spacing=10)
        
        progress = ft.ProgressRing(width=60, height=60, stroke_width=5, color="#BB86FC", bgcolor="#2D2D2D")
        step_text = ft.Text("Cargando...", size=18, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE)
        status_text = ft.Text("Inicializando...", size=14, color="#9E9E9E")
        
        loading = ft.Container(
            content=ft.Column([logo, ft.Container(height=40), progress, ft.Container(height=20), step_text, status_text], horizontal_alignment="center", spacing=0),
            alignment=ft.alignment.center,
            expand=True,
            bgcolor="#121212"
        )
        
        page.add(loading)
        page.update()
        
        # Delay original para mostrar pantalla de carga
        await asyncio.sleep(0.5)
        
        # Step 1: Config
        step_text.value = "2/5"
        status_text.value = "Configurando..."
        page.update()
        await asyncio.sleep(0.5)
        
        from config.config import get_settings
        settings = get_settings()
        status_text.value = "✓ Lista"
        page.update()
        
        await asyncio.sleep(0.5)
        
        # Step 2: Database
        step_text.value = "3/5"
        status_text.value = "Base de datos..."
        page.update()
        
        from usr.database.base import get_engine, get_session, init_local_tables, check_connection
        from usr.database.local_replica import LocalReplica
        from usr.database.sync import init_sync_manager
        
        await asyncio.sleep(0.1)
        from usr.views.login_view import LoginView
        setup_done = asyncio.Event()
        
        async def after_login():
            setup_done.set()
        
        usuario = await asyncio.to_thread(LocalReplica.get_usuario_dispositivo)
        
        if usuario is None:
            page.clean()
            login_view = LoginView(modo="registro", on_success=after_login)
            page.add(login_view)
            page.update()
            await setup_done.wait()
        elif usuario.get("pin_hash"):
            page.clean()
            login_view = LoginView(modo="pin", on_success=after_login)
            page.add(login_view)
            page.update()
            await setup_done.wait()
        else:
            page.session.set("username", usuario.get("nombre", "Operador"))
        
        # Restaurar pantalla de carga tras login exitoso
        page.clean()
        page.add(loading)
        if page.session.get("username"):
            status_text.value = f"✓ Hola, {page.session.get('username')}"
        else:
            status_text.value = f"✓ Hola, {page.session.get('username', 'Usuario')}"
        page.update()
        await asyncio.sleep(0.5)
        
        # Inicializando manager para sincronización
        sync_manager = init_sync_manager(get_engine)
        sync_manager.set_session_local_getter(get_session)
        status_text.value = "✓ Conectado"
        page.update()
        
        await asyncio.sleep(0.5)
        
        # Step 4: Sincronizando (original paso 4)
        step_text.value = "4/5"
        status_text.value = "Sincronizando..."
        page.update()
        
        if check_connection():
            try:
                # Utilizamos loop asíncrono puro como lo habías propuesto pero de forma segura
                await asyncio.to_thread(sync_manager.full_sync)
                status_text.value = "✓ Sincronizado"
            except Exception as e:
                print(f"Error en sync inicial: {e}")
                status_text.value = " Sin sync"
        else:
            status_text.value = " Modo offline"
        page.update()
        
        await asyncio.sleep(0.5)
        
        # Step 5: Views import
        step_text.value = "5/5"
        status_text.value = "Modulos..."
        page.update()
        
        await asyncio.sleep(0.5)
        from usr.views import InventarioView, ValidacionView, StockView, ConfiguracionView, HistorialFacturasView, RequisicionesView
        status_text.value = "✓ Cargado"
        page.update()

        # Step Create views
        await asyncio.sleep(0.5)
        status_text.value = "Creando..."
        page.update()
        
        await asyncio.sleep(0.5)
        inventario_view = InventarioView()
        requisiciones_view = RequisicionesView()
        requisiciones_view.inventario_view = inventario_view

        vistas = {0: inventario_view, 1: ValidacionView(), 2: StockView(), 3: requisiciones_view, 4: HistorialFacturasView(), 5: ConfiguracionView()}
        
        app_instance = ControlEntradasSalidasApp()
        requisiciones_view.app_controller = app_instance
        status_text.value = "✓ Creado"
        page.update()
        
        await asyncio.sleep(0.5)
        
        # Done
        step_text.value = "Listo!"
        page.update()
        await asyncio.sleep(0.5)

        status_text.value = "Iniciando..."
        page.update()
        await asyncio.sleep(0.5)
        
        await app_instance.arrancar_interfaz(page, settings, vistas)
        
    except Exception as inner_e:
        error_log = traceback.format_exc()
        db_dir = page.session.get("_db_dir") or "."
        try:
            log_path = os.path.join(db_dir, "error_log.txt")
            with open(log_path, "w") as f:
                f.write(error_log)
        except:
            pass
        mostrar_error_critico(page, error_log)

if __name__ == "__main__":
    ft.app(target=main, assets_dir="assets")