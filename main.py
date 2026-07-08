import flet as ft
import traceback
import os
import ssl
import certifi
import glob
import asyncio
import sys

# Esto le dice a Python exactamente dónde encontrar los certificados
os.environ['SSL_CERT_FILE'] = certifi.where()


def resource_path(relative_path: str) -> str:
    """Obtiene ruta absoluta de recursos para PyInstaller y desarrollo."""
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), relative_path)


from usr.updater import comprobar_y_aplicar_actualizaciones, _get_app_dir


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
        self.views = []
        self._layout_row = None
        self.settings = None
        self._switching_view = False
        
    async def arrancar_interfaz(self, page: ft.Page, settings, vistas_cargadas):
        self.page = page
        self.settings = settings
        
        # Asegurar que la base de datos local esté actualizada antes de cargar las vistas
        from usr.database.base import init_local_tables
        init_local_tables()
        
        # IMPORTANTE: Instanciamos las vistas aquí mismo para evitar que se pierdan
        from usr.views import InventarioView, ValidacionView, StockView, ProduccionesView, ConfiguracionView, HistorialFacturasView, RequisicionesView, BandejaWhatsAppView
        v_inv = InventarioView()
        v_val = ValidacionView()
        v_sto = StockView()
        v_pro = ProduccionesView()
        v_req = RequisicionesView()
        v_his = HistorialFacturasView()
        v_cfg = ConfiguracionView()
        v_ban = BandejaWhatsAppView()
        v_req.inventario_view = v_inv
        v_req.app_controller = self
        
        # Usamos una LISTA para garantizar que los índices sean exactos y no falte ninguno
        self.views = [
            v_inv,    # 0
            v_val,    # 1
            v_sto,    # 2
            v_pro,    # 3
            v_req,    # 4
            v_his,    # 5
            v_cfg,    # 6
            v_ban     # 7
        ]
        
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
                ft.NavigationRailDestination(icon=ft.Icons.FACTORY_OUTLINED, selected_icon=ft.Icons.FACTORY, label="Producciones"),
                ft.NavigationRailDestination(icon=ft.Icons.LOCAL_SHIPPING_OUTLINED, selected_icon=ft.Icons.LOCAL_SHIPPING, label="Requisiciones"),
                ft.NavigationRailDestination(icon=ft.Icons.HISTORY_OUTLINED, selected_icon=ft.Icons.HISTORY, label="Historial"),
                ft.NavigationRailDestination(icon=ft.Icons.SETTINGS_OUTLINED, selected_icon=ft.Icons.SETTINGS, label="Ajustes"),
                ft.NavigationRailDestination(icon=ft.Icons.MAIL_OUTLINED, selected_icon=ft.Icons.MAIL, label="Bandeja"),
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
        if getattr(self, '_switching_view', False):
            return
            
        if isinstance(e.control, ft.NavigationBar):
            index = int(e.control.selected_index)
            if index == 3:
                self._show_more_menu()
                return
            self.current_view_index = index
            self._show_view(index)
            return

        if isinstance(e.control, ft.NavigationRail):
            selected_dest = e.control.destinations[e.control.selected_index]
            label = selected_dest.label
            mapping = {
                "Inventario": 0,
                "Validación": 1,
                "Stock": 2,
                "Producciones": 3,
                "Requisiciones": 4,
                "Historial": 5,
                "Ajustes": 6,
                "Bandeja": 7
            }
            index = mapping.get(label)
            if index is None: return
            self.current_view_index = index
            self._show_view(index)

    def _show_more_menu(self):
        if self.page is None:
            return
            
        opciones = [("factory", "Producciones", 3), ("assignment", "Requisiciones", 4), ("history", "Historial", 5), ("settings", "Ajustes", 6), ("mail", "Bandeja", 7)]
        
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
        if getattr(self, '_switching_view', False):
            return
        self._switching_view = True
        try:
            if not self.views or index < 0 or index >= len(self.views):
                keys = list(range(len(self.views))) if self.views else "None"
                self.content_area.content = ft.Container(
                    content=ft.Text(f"Error: Vista {index} no encontrada. Keys: {keys}", color=ft.Colors.RED),
                    alignment=ft.alignment.center, expand=True
                )
                self.page.update()
                return
            view = self.views[index]
            
            if self.current_view: 
                self.current_view.visible = False
                
            self.content_area.content = view
            view.visible = True
            self.current_view = view
            self.current_view_index = index
            
            if self.navigation_bar:
                if index < 3:
                    self.navigation_bar.selected_index = index
                else:
                    self.navigation_bar.selected_index = 3
        finally:
            self._switching_view = False
        
        # LOGICA RESTAURADA: Actualizar indicador de conexión si existe en la vista
        if hasattr(view, '_update_connection_indicator'):
            try:
                if hasattr(view, '_connection_indicator') and view._connection_indicator in self.page.controls:
                    view._update_connection_indicator()
            except:
                pass
        
        self.page.update()


async def main(page: ft.Page):
    # Silenciar mensajes molestos de asyncio
    loop = asyncio.get_running_loop()
    if loop.get_debug():
        loop.set_debug(False)
    _old_handler = loop.get_exception_handler()
    def _filter_asyncio_warnings(_loop, context):
        if 'Task was destroyed' in context.get('message', ''):
            return
        if _old_handler:
            _old_handler(_loop, context)
        else:
            loop.default_exception_handler(context)
    loop.set_exception_handler(_filter_asyncio_warnings)

    # ✓ FONDO OSCURO DESDE EL PRIMER MOMENTO (evita white flash)
    page.bgcolor = "#121212"
    page.theme_mode = ft.ThemeMode.DARK
    
    # ✓ Inicializar page y error handler
    from usr.error_handler import set_page
    set_page(page)
    
    page.title = "Lycoris Control"
    page.favicon = "favicon.png"
    page.assets_allow_override = True
    
    page.window.icon = resource_path("assets/icono.ico")
    
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
        from usr.database.conn import set_db_path, get_db_path
        
        # Solo en Android usar app_data_dir (donde la app tiene permisos)
        db_dir = "."
        try:
            platform = getattr(page, 'platform', None)
            if platform and str(platform) in ('android', 'ios', 'android_tv'):
                if hasattr(page, 'app_data_dir') and page.app_data_dir:
                    db_dir = page.app_data_dir
        except:
            pass
        
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
            ft.Image(src="icono.png", width=120, height=120, fit=ft.ImageFit.CONTAIN, error_content=ft.Text("Logo no encontrado", color=ft.Colors.RED)),
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
        
        # Step 0: Comprobar actualizaciones dinámicas antes de importar la lógica
        try:
            await comprobar_y_aplicar_actualizaciones(page, status_text)
        except Exception as e_up:
            print(f"[LAUNCHER] Error ejecutando actualizador: {e_up}")
            
        # Inyectar la carpeta de actualizaciones al sys.path y redirigir usr.__path__
        updates_dir = os.path.join(_get_app_dir(), "app_updates")
        if os.path.exists(updates_dir):
            sys.path.insert(0, updates_dir)
            updates_usr = os.path.join(updates_dir, "usr")
            if os.path.exists(updates_usr):
                import usr
                usr.__path__ = [os.path.abspath(updates_usr)]
            print(f"[LAUNCHER] Cargando código actualizado desde {updates_dir}")
        
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
        
        # NO iniciar background sync aquí - se hace después de registrar callbacks
        is_online = check_connection()
        print(f"[MAIN] check_connection(): {is_online}")
        
        if is_online:
            status_text.value = "✓ Conectado"
        else:
            status_text.value = " Modo offline"
        
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
        from usr.views import InventarioView, ValidacionView, StockView, ProduccionesView, ConfiguracionView, HistorialFacturasView, RequisicionesView, BandejaWhatsAppView
        status_text.value = "✓ Cargado"
        page.update()
        
        # El resto de la creación de vistas y callbacks ahora ocurre dentro de app_instance.arrancar_interfaz
        app_instance = ControlEntradasSalidasApp()
        status_text.value = "✓ Creado"
        page.update()
        
        await asyncio.sleep(0.5)
        
        # Done
        step_text.value = "Listo!!!"
        page.update()
        await asyncio.sleep(0.5)
        
        status_text.value = "Iniciando..."
        page.update()
        await asyncio.sleep(0.5)
        
        await app_instance.arrancar_interfaz(page, settings, None)
        
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
    ft.app(target=main, assets_dir=resource_path("assets"))