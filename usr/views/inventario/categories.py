import flet as ft
from usr.views.inventario.helpers import generar_color, get_safe_colors


def get_card_bg(page):
    if page and page.theme_mode == ft.ThemeMode.LIGHT:
        return '#F0F4F8'
    return '#2D2D2D'


def create_categoria_card(categoria, colors, on_click_cb):
    nombre = getattr(categoria, 'nombre', '') or 'SIN NOMBRE'
    cat_color = getattr(categoria, 'color', None) or '#00FF00'
    inicial = nombre[0].upper() if nombre else "?"

    content_col = ft.Column(
        [
            ft.Container(
                content=ft.Text(inicial, size=22, weight="bold", color=ft.Colors.WHITE),
                width=45, height=45, bgcolor=cat_color,
                border_radius=25, alignment=ft.alignment.center,
            ),
            ft.Text(nombre.upper(), size=10, weight="bold", color=ft.Colors.WHITE, text_align="center"),
        ],
        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
        spacing=5,
    )

    card = ft.Container(
        content=content_col,
        bgcolor='#2D2D2D',
        width=110, height=130,
        border_radius=12, padding=10,
        border=ft.border.only(bottom=ft.BorderSide(4, cat_color)),
    )
    card.on_click = lambda e: on_click_cb(categoria)
    return card


def al_pasar_mouse(e, card, cat_color):
    if e.data == "true":
        card.scale = 1.05
        card.rotate = 0.02
        card.shadow = ft.BoxShadow(
            blur_radius=15,
            color=ft.Colors.with_opacity(0.2, cat_color),
            offset=ft.Offset(0, 0),
        )
        card.animate = ft.Animation(300, ft.AnimationCurve.DECELERATE)
    else:
        card.scale = 1.0
        card.rotate = 0
        card.shadow = ft.BoxShadow(
            blur_radius=0,
            color=ft.Colors.with_opacity(0.1, cat_color),
            offset=ft.Offset(0, 0),
        )
        card.animate = ft.Animation(300, ft.AnimationCurve.DECELERATE)
    card.update()


def create_categoria_card_from_dict(cat_dict, colors, on_click_cb):
    nombre = cat_dict.get("nombre", "")
    cat_color = cat_dict.get("color") or generar_color(nombre)
    inicial = nombre[0].upper() if nombre else "?"
    card_bg = colors['card']
    text_color = colors['text_primary']

    card = ft.Container(
        bgcolor=card_bg,
        border_radius=12,
        padding=12,
        width=110, height=130,
        alignment=ft.alignment.center,
        border=ft.border.only(bottom=ft.BorderSide(3, cat_color)),
        shadow=ft.BoxShadow(
            blur_radius=0,
            color=ft.Colors.with_opacity(0.2, cat_color),
            offset=ft.Offset(0, 3),
        ),
        animate_scale=ft.Animation(400, ft.AnimationCurve.DECELERATE),
        animate_rotation=ft.Animation(400, ft.AnimationCurve.DECELERATE),
        content=ft.Column(
            horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            alignment=ft.MainAxisAlignment.CENTER,
            controls=[
                ft.Container(
                    content=ft.Text(inicial, size=20, weight="bold", color=ft.Colors.WHITE),
                    alignment=ft.alignment.center,
                    width=40, height=40,
                    bgcolor=cat_color,
                    shape=ft.BoxShape.CIRCLE,
                    shadow=ft.BoxShadow(
                        blur_radius=8,
                        color=ft.Colors.with_opacity(0.3, cat_color),
                        offset=ft.Offset(0, 3)
                    )
                ),
                ft.Container(height=8),
                ft.Text(
                    str(nombre).upper(),
                    size=10, weight="bold",
                    color=text_color,
                    text_align=ft.TextAlign.CENTER,
                    max_lines=2,
                    overflow=ft.TextOverflow.ELLIPSIS
                ),
            ]
        )
    )
    card.on_hover = lambda e: al_pasar_mouse(e, card, cat_color)
    card.on_click = lambda e: on_click_cb(cat_dict)
    return card
