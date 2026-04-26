"""
Sistema global de manejo y notificación de errores.
"""
import traceback
import flet as ft

_page_ref = None
_banner_ref = None

def set_page(page: ft.Page):
    """Registrar la página activa. Llamar desde main.py al iniciar."""
    global _page_ref
    _page_ref = page

def show_error(mensaje: str, excepcion: Exception = None, contexto: str = ""):
    """Muestra el error en consola Y en pantalla como SnackBar rojo."""
    print(f"[ERROR] {contexto}: {mensaje}")
    if excepcion:
        traceback.print_exc()

    if _page_ref:
        try:
            detalle = f" — {type(excepcion).__name__}" if excepcion else ""
            snack = ft.SnackBar(
                content=ft.Row([
                    ft.Icon(ft.Icons.ERROR_OUTLINE, color=ft.Colors.WHITE, size=20),
                    ft.Text(f"{mensaje}{detalle}", color=ft.Colors.WHITE, size=13, expand=True),
                ]),
                bgcolor=ft.Colors.RED_700,
                duration=5000,
                show_close_icon=True,
            )
            _page_ref.overlay.append(snack)
            snack.open = True
            _page_ref.update()
        except Exception as inner:
            print(f"[ERROR_HANDLER] No se pudo mostrar en pantalla: {inner}")

def show_sync_error(mensaje: str):
    """Banner persistente para errores de sincronización."""
    global _banner_ref
    if not _page_ref:
        return
    try:
        def _close_banner():
            if _page_ref and _page_ref.banner:
                _page_ref.banner.open = False
                _page_ref.update()

        banner = ft.Banner(
            bgcolor=ft.Colors.ORANGE_700,
            leading=ft.Icon(ft.Icons.SYNC_PROBLEM, color=ft.Colors.WHITE, size=30),
            content=ft.Text(mensaje, color=ft.Colors.WHITE),
            actions=[
                ft.TextButton("Cerrar", style=ft.ButtonStyle(color=ft.Colors.WHITE), on_click=lambda e: _close_banner()),
            ],
        )
        _page_ref.banner = banner
        _page_ref.banner.open = True
        _page_ref.update()
    except Exception as e:
        print(f"[ERROR_HANDLER] Banner falló: {e}")