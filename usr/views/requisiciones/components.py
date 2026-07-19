import flet as ft
from datetime import datetime

from usr.views.requisiciones.data import contar_detalles


def _parse_dt(val):
    """Convierte fecha (datetime o string ISO) a datetime de forma segura."""
    if val is None:
        return None
    if isinstance(val, datetime):
        return val
    if isinstance(val, str):
        s = val.replace('Z', '').strip()
        for fmt in ('%Y-%m-%dT%H:%M:%S.%f', '%Y-%m-%d %H:%M:%S.%f',
                    '%Y-%m-%dT%H:%M:%S', '%Y-%m-%d %H:%M:%S',
                    '%Y-%m-%d'):
            try:
                return datetime.strptime(s[:len(fmt) + 6] if '.' in fmt else s[:19], fmt)
            except Exception:
                continue
    return None


def build_requisicion_card(req, callbacks, colors):
    """Tarjeta de una requisición en la lista."""
    estado_colors_map = {
        "pendiente": colors['warning'],
        "completada": colors['success'],
        "cancelada": colors['error'],
    }
    estado_color = estado_colors_map.get(req.estado, colors['text_secondary'])

    total_items = 0
    try:
        total_items = contar_detalles(req.id)
    except Exception:
        pass

    # Botones de acción según el estado
    actions = []
    
    # 1. Visualizar siempre disponible
    actions.append(ft.TextButton("Visualizar", on_click=callbacks["on_visualizar"]))
    
    # 2. Editar, Auditar y Eliminar solo si está pendiente
    if req.estado == "pendiente":
        actions.append(ft.TextButton("Editar", on_click=callbacks["on_editar"]))
        actions.append(ft.TextButton("Auditar", on_click=callbacks["on_auditar"], 
                                     style=ft.ButtonStyle(color=colors['accent'])))
        actions.append(ft.TextButton("Eliminar", on_click=callbacks["on_eliminar"], 
                                     style=ft.ButtonStyle(color=colors['error'])))

    return ft.Container(
        content=ft.Column([
            ft.Row([
                ft.Container(
                    content=ft.Icon(ft.Icons.ASSIGNMENT_ROUNDED, size=24, color=colors['white']),
                    bgcolor=colors['accent'],
                    width=44, height=44, border_radius=10,
                    alignment=ft.alignment.center,
                ),
                ft.Column([
                    ft.Text(f"#{req.numero}", weight="bold", size=16, color=colors['text_primary'], max_lines=1, overflow=ft.TextOverflow.ELLIPSIS),
                    ft.Text(f"{req.origen} → {req.destino}", size=12, color=colors['text_secondary'], max_lines=1, overflow=ft.TextOverflow.ELLIPSIS),
                ], expand=True, spacing=0),
                ft.Column([
                    ft.Container(
                        content=ft.Text(req.estado.upper(), size=10, weight="bold", color=colors['white']),
                        bgcolor=estado_color, padding=ft.padding.symmetric(horizontal=8, vertical=4),
                        border_radius=5,
                    ),
                    ft.Text(f"{total_items} items", size=11, color=colors['text_secondary']),
                ], horizontal_alignment="center"),
            ]),
            ft.Divider(height=1, color=colors['border']),
            ft.Row([
                ft.Text(
                    f"Creada: {_parse_dt(req.fecha_creacion).strftime('%d/%m/%Y %H:%M') if _parse_dt(req.fecha_creacion) else '-'}",
                    size=11, color=colors['text_secondary'], expand=True,
                ),
            ]),
            ft.Row(actions, alignment=ft.MainAxisAlignment.END, spacing=5, wrap=True),
        ], spacing=8),
        padding=15,
        bgcolor=colors['card'],
        border_radius=12,
        border=ft.border.all(1, colors['border']),
        on_click=callbacks["on_visualizar"],
    )


def build_empty_state(colors):
    return ft.Container(
        content=ft.Column([
            ft.Icon(ft.Icons.INVENTORY_2_OUTLINED, size=50, color=colors['text_hint']),
            ft.Text("No hay requisiciones", color=colors['text_secondary']),
        ], horizontal_alignment="center"),
        padding=ft.padding.only(top=80),
        alignment=ft.alignment.top_center,
    )


def build_detalle_row(d, colors):
    return ft.Container(
        content=ft.Row([
            ft.Text(d.ingrediente, weight="bold", expand=True),
            ft.Text(f"{d.cantidad:.2f} {d.unidad}", color=colors['accent']),
        ]),
        padding=10,
        bgcolor=colors['bg'],
        border_radius=8,
    )


def build_producto_busqueda_item(producto, on_agregar, colors):
    return ft.Container(
        content=ft.Row([
            ft.Column([
                ft.Text(producto.nombre, weight="bold", size=14, expand=True),
                ft.Text(f"Unidad: {producto.unidad_medida or 'unidad'}", size=11, color=colors['text_secondary']),
            ], expand=True),
            ft.IconButton(ft.Icons.ADD_CIRCLE, icon_color=colors['success'],
                          on_click=lambda _, p=producto: on_agregar(p)),
        ]),
        padding=10,
        bgcolor=colors['bg'],
        border_radius=8,
        on_click=lambda _, p=producto: on_agregar(p),
    )
