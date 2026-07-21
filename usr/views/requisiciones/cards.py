import flet as ft
from usr.models import Requisicion
from usr.theme import get_colors


def _c(page):
    return get_colors(page)


def build_requisicion_card(req, page, on_ver=None, on_editar=None, on_click=None):
    colors = _c(page)
    card_bg = '#2D2D2D'
    text_primary = ft.Colors.WHITE
    text_secondary = '#AAAAAA'

    estado_colors = {
        "pendiente": '#FF9800',
        "completada": '#4CAF50',
        "cancelada": '#F44336',
    }
    estado_color = estado_colors.get(req.estado, text_secondary)

    return ft.Container(
        content=ft.Column([
            ft.Row([
                ft.Container(
                    content=ft.Icon(ft.Icons.ASSIGNMENT_ROUNDED, size=24, color=ft.Colors.WHITE),
                    bgcolor=ft.Colors.DEEP_PURPLE_400,
                    width=44, height=44, border_radius=10,
                    alignment=ft.alignment.center,
                ),
                ft.Column([
                    ft.Text(f"#{req.numero}", weight="bold", size=16, color=text_primary),
                    ft.Text(f"{req.origen} → {req.destino}", size=12, color=text_secondary),
                ], expand=True, spacing=0),
                ft.Column([
                    ft.Container(
                        content=ft.Text(req.estado.upper(), size=10, weight="bold", color=ft.Colors.WHITE),
                        bgcolor=estado_color, padding=ft.padding.symmetric(horizontal=8, vertical=4),
                        border_radius=5,
                    ),
                    ft.Text(f"{len(getattr(req, 'detalles', []) or [])} items", size=11, color=text_secondary),
                ], horizontal_alignment="center"),
            ]),
            ft.Divider(height=1, color='#3D3D3D'),
            ft.Row([
                ft.Text(
                    f"Creada: {req.fecha_creacion.strftime('%d/%m/%Y %H:%M') if req.fecha_creacion else '-'}",
                    size=11, color=text_secondary, expand=True
                ),
                ft.Row([
                    ft.TextButton("Ver", on_click=lambda _: on_ver(req) if on_ver else None),
                    ft.TextButton("Editar", on_click=lambda _: on_editar(req) if on_editar else None),
                ], spacing=5),
            ]),
        ], spacing=8),
        padding=15,
        bgcolor=card_bg,
        border_radius=12,
        border=ft.border.all(1, '#3D3D3D'),
        on_click=lambda _: on_click(req) if on_click else None,
    )


def build_producto_item_row(item, index, page, on_delete=None):
    colors = _c(page)
    es_pesable = item.get('es_pesable', False)
    cantidad = item['cantidad']
    unidad = item['unidad']

    if es_pesable:
        display_text = f"{cantidad:.2f} kg"
    else:
        display_text = f"{int(cantidad) if cantidad == int(cantidad) else cantidad:.2f} {unidad}"

    return ft.Container(
        content=ft.Row([
            ft.Column([
                ft.Text(f"{index+1}. {item['nombre']}", size=13, weight="bold", color=colors['text_primary']),
                ft.Text(display_text, size=11, color=colors['accent']),
            ], expand=True),
            ft.IconButton(
                ft.Icons.DELETE_OUTLINE,
                icon_color=colors['error'],
                icon_size=20,
                on_click=lambda _: on_delete(index) if on_delete else None,
            ),
        ], spacing=10),
        padding=12,
        bgcolor=colors['card'],
        border_radius=10,
    )
