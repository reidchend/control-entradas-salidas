import flet as ft

from usr.views.requisiciones.data import contar_detalles


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
                    ft.Text(f"#{req.numero}", weight="bold", size=16, color=colors['text_primary']),
                    ft.Text(f"{req.origen} → {req.destino}", size=12, color=colors['text_secondary']),
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
                    f"Creada: {req.fecha_creacion.strftime('%d/%m/%Y %H:%M') if req.fecha_creacion else '-'}",
                    size=11, color=colors['text_secondary'], expand=True,
                ),
                ft.Row([
                    ft.TextButton("Ver", on_click=callbacks["on_ver"]),
                    ft.TextButton("Editar", on_click=callbacks["on_editar"]),
                ], spacing=5),
            ]),
        ], spacing=8),
        padding=15,
        bgcolor=colors['card'],
        border_radius=12,
        border=ft.border.all(1, colors['border']),
        on_click=callbacks["on_ver"],
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
