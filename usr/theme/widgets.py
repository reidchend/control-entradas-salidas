"""
Componentes de UI con soporte para temas dinámicos
"""
import flet as ft
from usr.theme import get_theme


class ThemedText(ft.Text):
    def __init__(self, text, size=14, weight=None, color_key='text_primary', **kwargs):
        colors = get_theme(True)
        super().__init__(
            text,
            size=size,
            color=colors[color_key],
            weight=weight,
            **kwargs
        )
        self.color_key = color_key

    def update_theme(self, is_dark: bool):
        colors = get_theme(is_dark)
        self.color = colors[self.color_key]


class ThemedContainer(ft.Container):
    def __init__(self, bgcolor_key='card', **kwargs):
        colors = get_theme(True)
        super().__init__(
            bgcolor=colors[bgcolor_key],
            **kwargs
        )
        self.bgcolor_key = bgcolor_key

    def update_theme(self, is_dark: bool):
        colors = get_theme(is_dark)
        self.bgcolor = colors[self.bgcolor_key]


class ThemedCard(ThemedContainer):
    def __init__(self, content=None, padding=10, border_radius=8, **kwargs):
        super().__init__(
            bgcolor_key='card',
            content=content,
            padding=padding,
            border_radius=border_radius,
            **kwargs
        )


def themed_text(text, size=14, weight=None, secondary=False, hint=False, **kwargs):
    """Helper rápido para crear texto con el tema actual"""
    if hint:
        color_key = 'text_hint'
    elif secondary:
        color_key = 'text_secondary'
    else:
        color_key = 'text_primary'
    return ThemedText(text, size=size, weight=weight, color_key=color_key, **kwargs)


def get_text_color(is_dark: bool, key='text_primary'):
    """Obtiene el color de texto para el tema actual"""
    return get_theme(is_dark)[key]
