import flet as ft
from usr.theme import get_colors

# Mapa de nombres de color estilo ft.Colors -> claves del tema dinámico
_COLOR_MAP = {
    'GREY_300': 'text_hint',
    'GREY_400': 'text_secondary',
    'GREY_500': 'text_secondary',
    'GREY_200': 'border',
    'GREY_50': 'bg',
    'BLUE_GREY_900': 'text_primary',
    'BLUE_GREY_800': 'text_primary',
    'BLUE_GREY_500': 'text_secondary',
    'BLUE_GREY_400': 'text_secondary',
    'WHITE': 'white',
    'BLUE_600': 'accent',
    'BLUE_700': 'accent',
    'GREEN_600': 'success',
    'GREEN_700': 'success',
    'RED_400': 'error',
    'RED_700': 'error',
    'ORANGE_600': 'warning',
    'ORANGE_700': 'warning',
}


def get_colors_safe(page):
    return get_colors(page)


def _colors(page):
    return get_colors(page)


def _get_color(page, color_name):
    """Obtiene color dinámico desde constantes de ft.Colors."""
    colors = _colors(page)
    key = _COLOR_MAP.get(color_name, 'text_primary')
    return colors.get(key, colors['text_primary'])


def _c(page, color_name):
    """Alias corto para _get_color."""
    return _get_color(page, color_name)


def is_mobile(page):
    return bool(page and page.width is not None and page.width < 700)
