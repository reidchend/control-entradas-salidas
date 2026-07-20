"""
Sistema centralizado de notificaciones para la aplicación.
Proporciona funciones unificadas para mostrar mensajes al usuario.
"""
import sys
import flet as ft

# Página activa (almacenada en sys para sobrevivir recargas de módulos)
_page = None

def _get_page():
    """Obtiene la página activa desde sys o desde la pila de llamadas."""
    global _page
    if _page is not None:
        return _page
    saved = getattr(sys, '_opencode_notif_page', None)
    if saved is not None:
        _page = saved
        return saved
    # Fallback: buscar page en la pila de llamadas (compilado sin fix)
    try:
        frame = sys._getframe()
        while frame:
            for val in frame.f_locals.values():
                if isinstance(val, ft.Page):
                    _page = val
                    return val
                if isinstance(val, ft.View):
                    if hasattr(val, 'page') and isinstance(val.page, ft.Page):
                        _page = val.page
                        return val.page
            frame = frame.f_back
    except:
        pass
    return None

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
    sys._opencode_notif_page = page


def _get_colors():
    """Obtener colores del tema (soporta tema claro/oscuro)."""
    page = _get_page()
    if page and hasattr(page, 'theme_mode') and page.theme_mode == ft.ThemeMode.LIGHT:
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
    if not _get_page():
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
        page = _get_page()
        # Cerrar cualquier snackbar anterior que esté abierto
        if page.overlay:
            for item in list(page.overlay):
                if isinstance(item, ft.SnackBar) and item.open:
                    try:
                        item.open = False
                    except:
                        pass

        page.overlay.append(snack)
        snack.open = True
        page.update()
    except Exception as e:
        print(f"[NOTIF] Error mostrando SnackBar: {e}")


def show_success(message: str, duration: int = None, with_icon: bool = True, action_text: str = None, action_callback = None):
    """Mostrar mensaje de éxito (verde)."""
    _show_snackbar(message, 'success', duration, with_icon, action_text, action_callback)


def show_error(message: str, duration: int = None, with_icon: bool = True, action_text: str = None, action_callback = None):
    """Mostrar mensaje de error (rojo)."""
    _show_snackbar(message, 'error', duration, with_icon, action_text, action_callback)


def show_error_with_copy(message: str, ex: Exception = None, duration: int = 6):
    """Mostrar mensaje de error con botón para copiar detalles al clipboard."""
    import traceback as tb
    detail_lines = [f"Error: {message}"]
    if ex:
        detail_lines.append(f"Tipo: {type(ex).__name__}")
        detail_lines.append("")
        detail_lines.extend(tb.format_exception(type(ex), ex, ex.__traceback__))
    full_detail = "\n".join(detail_lines)

    def _copy(e):
        try:
            p = _get_page()
            if p:
                p.set_clipboard(full_detail)
        except Exception:
            pass

    truncated = message[:100] + ("..." if len(message) > 100 else "")
    _show_snackbar(truncated, 'error', duration, True, "📋 Copiar", _copy)


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

    page = _get_page()
    if not page:
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
        p = _get_page()
        if p and p.banner:
            p.banner.open = False
            p.update()

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
        p = _get_page()
        # Cerrar banner anterior si existe
        if p.banner:
            p.banner.open = False

        p.banner = banner
        p.banner.open = True
        p.update()
        _active_banner = banner
    except Exception as e:
        print(f"[NOTIF] Error mostrando Banner: {e}")


def clear_notifications():
    """Limpiar todas las notificaciones activas."""
    page = _get_page()
    if not page:
        return

    try:
        # Cerrar SnackBars
        for item in list(page.overlay):
            if isinstance(item, ft.SnackBar):
                item.open = False

        # Cerrar Banner
        if page.banner:
            page.banner.open = False
            page.banner = None

        page.update()
    except Exception as e:
        print(f"[NOTIF] Error limpiando notificaciones: {e}")
