import flet as ft
from usr.logger import get_logger
from usr.database.local_replica import LocalReplica
from usr.theme import get_theme

logger = get_logger(__name__)

DARK_THEME = get_theme(True)


class LoginView(ft.Container):
    def __init__(self, on_success=None, modo="registro"):
        super().__init__()
        self.expand = True
        self.padding = ft.padding.all(20)
        self.bgcolor = DARK_THEME['bg']
        self.on_success_callback = on_success
        self.modo = modo
        
        self.nombre_input = ft.TextField(
            label="Nombre del operador",
            width=300,
            visible=(modo == "registro"),
            border_color=DARK_THEME['input_border'],
            focused_border_color=DARK_THEME['accent'],
            label_style=ft.TextStyle(color=DARK_THEME['text_secondary']),
            hint_style=ft.TextStyle(color=DARK_THEME['text_hint']),
            text_style=ft.TextStyle(color=DARK_THEME['input_text']),
        )
        self.pin_input = ft.TextField(
            label="PIN de 4 digitos",
            width=300,
            password=True,
            max_length=4,
            keyboard_type=ft.KeyboardType.NUMBER,
            border_color=DARK_THEME['input_border'],
            focused_border_color=DARK_THEME['accent'],
            label_style=ft.TextStyle(color=DARK_THEME['text_secondary']),
            hint_style=ft.TextStyle(color=DARK_THEME['text_hint']),
            text_style=ft.TextStyle(color=DARK_THEME['input_text']),
        )
        self.confirm_pin_input = ft.TextField(
            label="Confirmar PIN",
            width=300,
            password=True,
            max_length=4,
            keyboard_type=ft.KeyboardType.NUMBER,
            visible=(modo == "registro"),
            border_color=DARK_THEME['input_border'],
            focused_border_color=DARK_THEME['accent'],
            label_style=ft.TextStyle(color=DARK_THEME['text_secondary']),
            hint_style=ft.TextStyle(color=DARK_THEME['text_hint']),
            text_style=ft.TextStyle(color=DARK_THEME['input_text']),
        )
        self.error_text = ft.Text("", color=DARK_THEME['error'], size=12, visible=False, selectable=True)
        
        self._build_ui()
    
    def _build_ui(self):
        titulo = "Registro de Operador" if self.modo == "registro" else "Ingrese su PIN"
        subtitulo = "Configure el operador principal del dispositivo" if self.modo == "registro" else "Ingrese su PIN para continuar"
        
        btn_bgcolor = DARK_THEME['accent_dark']
        
        botones = [
            ft.ElevatedButton(
                "Registrar" if self.modo == "registro" else "Desbloquear",
                width=300,
                bgcolor=btn_bgcolor,
                color=DARK_THEME['white'],
                on_click=self._on_submit
            )
        ]
        
        if self.modo == "registro":
            botones.append(
                ft.TextButton(
                    "Omitir (sin PIN)",
                    on_click=self._omitir_pin,
                    style=ft.ButtonStyle(color=DARK_THEME['text_secondary'])
                )
            )
        
        self.content = ft.Column([
            ft.Container(height=60),
            ft.Column([
                ft.Icon(ft.Icons.PERSON_ROUNDED, size=60, color=DARK_THEME['accent']),
                ft.Text(titulo, size=28, weight="bold", color=DARK_THEME['text_primary']),
                ft.Text(subtitulo, size=14, color=DARK_THEME['text_secondary']),
            ], horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=10),
            
            ft.Container(height=40),
            
            ft.Column([
                self.nombre_input,
                self.pin_input,
                self.confirm_pin_input,
                self.error_text,
                ft.Container(height=10),
                *botones,
            ], horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=15),
            
            ft.Container(expand=True),
        ], horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=0)
    
    async def _on_submit(self, e):
        if self.modo == "registro":
            nombre = self.nombre_input.value
            pin = self.pin_input.value
            confirm = self.confirm_pin_input.value
            
            if not nombre or not nombre.strip():
                self._show_error("Ingrese el nombre del operador")
                return
            
            if pin and len(pin) != 4:
                self._show_error("El PIN debe tener 4 digitos")
                return
            
            if pin and pin != confirm:
                self._show_error("Los PINs no coinciden")
                return
            
            try:
                LocalReplica.registrar_usuario_dispositivo(nombre, pin)
                logger.info(f"Operador registrado: {nombre}")
                await self._go_to_main(nombre)
            except Exception as ex:
                self._show_error(f"Error: {str(ex)}")
        else:
            pin = self.pin_input.value
            
            if not pin:
                self._show_error("Ingrese el PIN")
                return
            
            if LocalReplica.verificar_pin(pin):
                usuario = LocalReplica.get_usuario_dispositivo()
                logger.info(f"Usuario desbloqueado: {usuario['nombre']}")
                await self._go_to_main(usuario['nombre'])
            else:
                self._show_error("PIN incorrecto")
    
    async def _omitir_pin(self, e):
        nombre = self.nombre_input.value or "Operador"
        
        try:
            LocalReplica.registrar_usuario_dispositivo(nombre, None)
            logger.info(f"Operador registrado sin PIN: {nombre}")
            await self._go_to_main(nombre)
        except Exception as ex:
            self._show_error(f"Error: {str(ex)}")
    
    async def _go_to_main(self, nombre):
        try:
            if self.page:
                self.page.session.set("username", nombre)
                self.page.clean()
                
                # Asegurar que la BD local existe
                from usr.database.local_replica import ensure_local_db
                ensure_local_db()
                
                # Importar aquí para evitar efectos secundarios
                from usr.database.base import get_engine, get_session, check_connection, init_local_tables
                from usr.database.sync import init_sync_manager
                from config.config import get_settings
                from usr.views import (
                    InventarioView, ValidacionView, StockView, 
                    ConfiguracionView, HistorialFacturasView, RequisicionesView
                )
                from main import ControlEntradasSalidasApp
                
                settings = get_settings()
                settings.LOCAL_DB_PATH = ""
                
                # Inicializar tablas SQLAlchemy local
                init_local_tables()
                
                # Sincronizar datos de Supabase
                sync_manager = init_sync_manager(get_engine)
                sync_manager.set_session_local_getter(get_session)
                
                if check_connection():
                    try:
                        import asyncio
                        await asyncio.to_thread(sync_manager.full_sync)
                        logger.info("Sync completado desde login")
                    except Exception as sync_err:
                        logger.error(f"Error en sync: {sync_err}")
                
                # Las vistas ya están cargadas en el device
                inventario_view = InventarioView()
                requisiciones_view = RequisicionesView()
                requisiciones_view.inventario_view = inventario_view
                vistas = {
                    0: inventario_view, 
                    1: ValidacionView(), 
                    2: StockView(), 
                    3: requisiciones_view, 
                    4: HistorialFacturasView(), 
                    5: ConfiguracionView()
                }
                
                app_instance = ControlEntradasSalidasApp()
                requisiciones_view.app_controller = app_instance
                
                # Arrancar la interfaz
                await app_instance.arrancar_interfaz(self.page, settings, vistas)
                
        except Exception as e:
            logger.error(f"Error al cargar app: {e}")
            import traceback
            traceback.print_exc()
            self._show_error(f"Error: {str(e)}")
    
    def _show_error(self, message):
        self.error_text.value = message
        self.error_text.visible = True
        if self.page:
            self.page.update()