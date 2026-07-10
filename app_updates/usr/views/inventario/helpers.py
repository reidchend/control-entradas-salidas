import hashlib
import flet as ft
from usr.theme import get_theme, get_colors


def generar_color(texto):
    hash_hcl = hashlib.md5(texto.encode()).hexdigest()
    return f"#{hash_hcl[:6]}"


def get_attr(obj, key, default=""):
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)


def get_safe_colors(page=None):
    if page and hasattr(page, 'theme_mode'):
        return get_theme(page.theme_mode == ft.ThemeMode.DARK)
    return get_theme(True)
