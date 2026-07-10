"""
Constantes de colores para el tema de la aplicación
"""
import flet as ft


def get_colors(page):
    """Helper para obtener colores según el tema de la página"""
    if page and hasattr(page, 'theme_mode'):
        return get_theme(page.theme_mode == ft.ThemeMode.DARK)
    return get_theme(True)


def get_theme(is_dark: bool):
    """Retorna diccionario de colores según el tema"""
    if is_dark:
        return {
            'bg': '#1A1A1A',
            'surface': '#252525',
            'card': '#2D2D2D',
            'card_hover': '#3D3D3D',
            'text_primary': '#FFFFFF',
            'text_secondary': '#9E9E9E',
            'text_hint': '#666666',
            'border': '#3D3D3D',
            'accent': '#BB86FC',
            'accent_dark': '#9A67EA',
            'nav_bg': '#1E1E1E',
            'input_bg': '#2D2D2D',
            'input_border': '#3D3D3D',
            'input_text': '#FFFFFF',
            'input_hint': '#666666',
            'success': '#4CAF50',
            'warning': '#FF9800',
            'error': '#F44336',
            'info': '#2196F3',
            'white': '#FFFFFF',
            'black': '#000000',
            'blue_50': '#3D3D5C',
            'green_50': '#1B3B1B',
            'orange_50': '#4A3D2D',
        }
    else:
        return {
            'bg': '#F5F5F5',
            'surface': '#FFFFFF',
            'card': '#FFFFFF',
            'card_hover': '#F0F0F0',
            'text_primary': '#1A1A1A',
            'text_secondary': '#666666',
            'text_hint': '#999999',
            'border': '#E0E0E0',
            'accent': '#6200EE',
            'accent_dark': '#3700B3',
            'nav_bg': '#F3E5F5',
            'input_bg': '#FFFFFF',
            'input_border': '#E0E0E0',
            'input_text': '#1A1A1A',
            'input_hint': '#999999',
            'success': '#388E3C',
            'warning': '#F57C00',
            'error': '#D32F2F',
            'info': '#1976D2',
            'white': '#FFFFFF',
            'black': '#000000',
            'blue_50': '#E3F2FD',
            'green_50': '#E8F5E9',
            'orange_50': '#FFF3E0',
        }


def apply_theme_to_container(container, is_dark: bool):
    """Aplica el tema a un Container"""
    colors = get_theme(is_dark)
    container.bgcolor = colors['card']

def apply_theme_to_textfield(tf, is_dark: bool):
    """Aplica el tema a un TextField"""
    colors = get_theme(is_dark)
    tf.border_color = colors['input_border']
    tf.focused_border_color = colors['accent']
    tf.cursor_color = colors['accent']
    tf.text_color = colors['input_text']
    tf.hint_color = colors['input_hint']

def apply_theme_to_button(btn, is_dark: bool):
    """Aplica el tema a un ElevatedButton"""
    colors = get_theme(is_dark)
    btn.bgcolor = colors['accent']
    btn.color = colors['white']
