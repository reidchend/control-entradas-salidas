"""
Sistema global de manejo y notificación de errores.
Este módulo mantiene compatibilidad hacia atrás usando notifications.py internamente.
"""
import traceback
import flet as ft

# Importar el sistema de notificaciones centralizado
from usr.notifications import set_page as _set_page_notif, show_error as _show_error, show_banner as _show_banner

_page_ref = None
_banner_ref = None


def set_page(page: ft.Page):
    """Registrar la página activa. Llamar desde main.py al iniciar."""
    global _page_ref
    _page_ref = page
    _set_page_notif(page)


def show_error(mensaje: str, excepcion: Exception = None, contexto: str = ""):
    """Muestra el error en consola Y en pantalla como SnackBar rojo."""
    print(f"[ERROR] {contexto}: {mensaje}")
    if excepcion:
        traceback.print_exc()

    # Usar el sistema centralizado
    detalle = f" — {type(excepcion).__name__}" if excepcion else ""
    _show_error(f"{mensaje}{detalle}", duration=5)


def show_sync_error(mensaje: str):
    """Banner persistente para errores de sincronización."""
    _show_banner(mensaje, 'warning')