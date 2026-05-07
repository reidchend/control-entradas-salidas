"""
Sistema centralizado de notificaciones para la aplicación.
Proporciona funciones unificadas para mostrar mensajes al usuario.
"""
import flet as ft

# Página activa
_page = None

# Banner activo
_active_banner = None

# Duraciones por defecto (en segundos)
DEFAULT_DURATION = {
    'success': 3000,
    'error': 3000,
    'warning': 3000,
    'info': 3000,
}

# Iconos
ICONS = {
    'success': ft.Icons.CHECK_CIRCLE,
    'error': ft.Icons.ERROR,
    'warning': ft.Icons.WARNING,
    'info': ft.Icons.INFO,
}

# Colores
COLORS = {
    'success': '#4CAF50',
    'error': '#F44336',
    'warning': '#FF9800',
    'info': '#2196F3',
}


def set_page(page: ft.Page):
    """Registrar la página activa para mostrar notificaciones."""
    global _page
    _page = page


def _get_colors():
    """Obtener colores del tema (soporta tema claro/oscuro)."""
    if _page and hasattr(_page, 'theme_mode') and _page.theme_mode == ft.ThemeMode.LIGHT:
        return {
            'success': '#388E3C',
            'error': '#D32F2F',
            'warning': '#F57C00',
            'info': '#1976D2',
            'white': '#FFFFFF',
            'black': '#000000',
        }
    return {
        'success': '#4CAF50',
        'error': '#F44336',
        'warning': '#FF9800',
        'info': '#2196F3',
        'white': '#FFFFFF',
        'black': '#000000',
    }


def _show_snackbar(message: str, tipo: str, duration: int = None, with_icon: bool = True, action_text: str = None, action_callback = None):
    """Función interna para mostrar SnackBar.
    
    Args:
        action_text: Texto para botón de acción (ej: "Copiar")
        action_callback: Función callback al presionar botón
    """
    if not _page:
        print(f"[NOTIF] {tipo.upper()}: {message}")
        return

    if duration is None:
        duration = DEFAULT_DURATION.get(tipo, 4)

    colors = _get_colors()
    bgcolor = colors.get(tipo, COLORS[tipo])

    content_parts = []

    if with_icon:
        icon_color = colors['white']
        content_parts.append(
            ft.Icon(ICONS.get(tipo, ft.Icons.INFO), color=icon_color, size=20)
        )

    content_parts.append(ft.Text(message, color=colors['white'], size=14, expand=True))

    snack = ft.SnackBar(
        content=ft.Row(content_parts, spacing=10, expand=True),
        bgcolor=bgcolor,
        duration=duration,
        action=action_text if action_text else None,
        on_action=action_callback,
        show_close_icon=True,
        behavior=ft.SnackBarBehavior.FLOATING,
    )

    try:
        # Cerrar cualquier snackbar anterior
        if _page.overlay:
            for item in list(_page.overlay):
                if isinstance(item, ft.SnackBar):
                    item.open = False

        _page.overlay.append(snack)
        snack.open = True
        _page.update()
    except Exception as e:
        print(f"[NOTIF] Error mostrando SnackBar: {e}")


def show_success(message: str, duration: int = None, with_icon: bool = True, action_text: str = None, action_callback = None):
    """Mostrar mensaje de éxito (verde)."""
    _show_snackbar(message, 'success', duration, with_icon, action_text, action_callback)


def show_error(message: str, duration: int = None, with_icon: bool = True, action_text: str = None, action_callback = None):
    """Mostrar mensaje de error (rojo)."""
    _show_snackbar(message, 'error', duration, with_icon, action_text, action_callback)


def show_warning(message: str, duration: int = None, with_icon: bool = True, action_text: str = None, action_callback = None):
    """Mostrar mensaje de advertencia (naranja)."""
    _show_snackbar(message, 'warning', duration, with_icon, action_text, action_callback)


def show_info(message: str, duration: int = None, with_icon: bool = True, action_text: str = None, action_callback = None):
    """Mostrar mensaje informativo (azul)."""
    _show_snackbar(message, 'info', duration, with_icon, action_text, action_callback)


def show_banner(message: str, tipo: str = 'info'):
    """Mostrar banner persistente que requiere acción del usuario.
    
    Tipos: 'success', 'error', 'warning', 'info'
    """
    global _active_banner

    if not _page:
        print(f"[NOTIF BANNER] {tipo.upper()}: {message}")
        return

    colors = _get_colors()
    color_map = {
        'success': colors['success'],
        'error': colors['error'],
        'warning': colors['warning'],
        'info': colors['info'],
    }
    icon_map = {
        'success': ft.Icons.CHECK_CIRCLE,
        'error': ft.Icons.ERROR,
        'warning': ft.Icons.WARNING,
        'info': ft.Icons.INFO,
    }

    bgcolor = color_map.get(tipo, colors['info'])
    icon = icon_map.get(tipo, ft.Icons.INFO)

    def close_banner(e):
        if _page and _page.banner:
            _page.banner.open = False
            _page.update()

    banner = ft.Banner(
        bgcolor=bgcolor,
        leading=ft.Icon(icon, color=colors['white'], size=30),
        content=ft.Text(message, color=colors['white'], size=14),
        actions=[
            ft.TextButton(
                "Cerrar",
                style=ft.ButtonStyle(color=colors['white']),
                on_click=close_banner
            ),
        ],
    )

    try:
        # Cerrar banner anterior si existe
        if _page.banner:
            _page.banner.open = False

        _page.banner = banner
        _page.banner.open = True
        _page.update()
        _active_banner = banner
    except Exception as e:
        print(f"[NOTIF] Error mostrando Banner: {e}")


def clear_notifications():
    """Limpiar todas las notificaciones activas."""
    if not _page:
        return

    try:
        # Cerrar SnackBars
        for item in list(_page.overlay):
            if isinstance(item, ft.SnackBar):
                item.open = False

        # Cerrar Banner
        if _page.banner:
            _page.banner.open = False
            _page.banner = None

        _page.update()
    except Exception as e:
        print(f"[NOTIF] Error limpiando notificaciones: {e}")