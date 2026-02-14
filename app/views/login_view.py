import flet as ft
from app.logger import get_logger

logger = get_logger(__name__)

class LoginView(ft.Container):
    def __init__(self):
        super().__init__()
        self.expand = True
        self.padding = ft.padding.all(20)
        self.bgcolor = ft.Colors.GREY_50
        
        # Variables
        self.user_input = ft.TextField(label="Usuario", width=300)
        self.pass_input = ft.TextField(label="Contraseña", password=True, width=300)
        
        self._build_ui()
    
    def _build_ui(self):
        self.content = ft.Column([
            ft.Container(height=50),  # Espaciador
            ft.Column([
                ft.Icon(ft.Icons.LOCK_ROUNDED, size=60, color=ft.Colors.PRIMARY),
                ft.Text("Lycoris Control", size=28, weight="bold"),
                ft.Text("Sistema de Inventario", size=14, color=ft.Colors.GREY_500),
            ], horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=10),
            
            ft.Container(height=40),
            
            ft.Column([
                self.user_input,
                self.pass_input,
                ft.ElevatedButton(
                    "Iniciar Sesión",
                    width=300,
                    on_click=self._on_login
                ),
            ], horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=15),
            
            ft.Container(expand=True),
        ], horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=0)
    
    def _on_login(self, e):
        username = self.user_input.value
        password = self.pass_input.value
        
        if not username or not password:
            self._show_error("Completa todos los campos")
            return
        
        logger.info(f"Intento de login del usuario: {username}")
        
        # Aquí implementar la lógica de autenticación
        # Por ahora, aceptar cualquier usuario
        if self.page:
            self.page.session.set("user_id", 1)
            self.page.session.set("username", username)
            # Notificar al app principal que se autenticó
            logger.info(f"Usuario {username} autenticado exitosamente")
    
    def _show_error(self, message):
        if self.page:
            self.page.show_snack_bar(
                ft.SnackBar(
                    content=ft.Text(message),
                    bgcolor=ft.Colors.RED_700
                )
            )