import flet as ft
from datetime import datetime
from usr.database.sync_queue import get_sync_queue
from usr.database.local_replica import LocalReplica
from usr.notifications import show_success, show_error
from usr.views.configuracion.helpers import _colors, trigger_sync
from usr.views.configuracion.dialogs import close_dialog, add_to_overlay, confirm_delete


def show_categoria_dialog(view, categoria=None):
    colors = _colors(view.page)
    view.selected_image_path = None
    is_mobile = view.page.width < 600

    nombre_field = ft.TextField(
        label="Nombre",
        value=categoria.nombre if categoria else "",
        border=ft.InputBorder.OUTLINE,
        border_radius=10,
        prefix_icon=ft.Icons.CATEGORY,
        capitalization=ft.TextCapitalization.WORDS,
        expand=is_mobile,
    )

    descripcion_field = ft.TextField(
        label="Descripcion",
        value=categoria.descripcion if categoria else "",
        multiline=True,
        max_length=255,
        border=ft.InputBorder.OUTLINE,
        border_radius=10,
        min_lines=2,
        max_lines=4,
        prefix_icon=ft.Icons.DESCRIPTION,
        expand=is_mobile,
    )

    colores = [
        ("#2196F3", "Azul"),
        ("#F44336", "Rojo"),
        ("#4CAF50", "Verde"),
        ("#FF9800", "Naranja"),
        ("#9C27B0", "Morado"),
        ("#00BCD4", "Cyan"),
        ("#E91E63", "Rosa"),
        ("#795548", "Marron"),
    ]

    color_options = [ft.dropdown.Option(c[0], c[1]) for c in colores]
    color_dropdown = ft.Dropdown(
        label="Color",
        options=color_options,
        value=categoria.color if categoria else "#2196F3",
        border=ft.InputBorder.OUTLINE,
        border_radius=10,
        prefix_icon=ft.Icons.PALETTE,
        expand=True,
    )

    color_preview = ft.Row(
        controls=[
            ft.GestureDetector(
                content=ft.Container(
                    width=30 if is_mobile else 35,
                    height=30 if is_mobile else 35,
                    bgcolor=c[0],
                    border_radius=20,
                    border=ft.border.all(2, colors['white'] if c[0] == color_dropdown.value else "transparent"),
                ),
                on_tap=lambda e, color=c[0]: _update_color_preview(view, color, color_preview, color_dropdown),
            )
            for c in colores
        ],
        spacing=6 if is_mobile else 8,
        wrap=True,
    )

    activo_sw = ft.Switch(
        label="Activa",
        value=categoria.activo if categoria else True,
        active_color=colors['success'],
    )

    def save_click(e):
        if not nombre_field.value or not nombre_field.value.strip():
            nombre_field.error_text = "Requerido"
            nombre_field.update()
            return
        save_categoria(
            view,
            nombre_field.value.strip(),
            descripcion_field.value.strip(),
            color_dropdown.value,
            activo_sw.value,
            categoria.id if categoria else None
        )
        close_dialog(view)
        if callable(getattr(view, '_load_data', None)):
            view._load_data()

    dialog_content = ft.Column([
        nombre_field,
        color_dropdown,
        color_preview,
        descripcion_field,
        ft.Divider(height=15, color=colors['border']),
        activo_sw,
    ], spacing=12 if is_mobile else 18, tight=True, scroll=ft.ScrollMode.AUTO)

    view.active_dialog = ft.AlertDialog(
        title=ft.Row([
            ft.Icon(ft.Icons.CATEGORY, color=colors['accent'], size=24 if is_mobile else 28),
            ft.Text(
                "Categoria" if is_mobile else "Gestionar Categoria",
                weight=ft.FontWeight.BOLD,
                size=16 if is_mobile else 18,
            ),
        ], spacing=8),
        content=ft.Container(
            content=dialog_content,
            width=None if is_mobile else 450,
            padding=5,
        ),
        actions=[
            ft.TextButton("Cancelar", on_click=lambda e: close_dialog(view, e)),
            ft.ElevatedButton(
                "Guardar",
                on_click=save_click,
                bgcolor=colors['accent'],
                color=colors['white'],
            ),
        ],
        actions_alignment=ft.MainAxisAlignment.END,
    )
    add_to_overlay(view, view.active_dialog)


def _update_color_preview(view, color, preview_row, dropdown=None):
    colors = _colors(view.page)
    if dropdown:
        dropdown.value = color
    for ctrl in preview_row.controls:
        container = ctrl.content
        container.border = ft.border.all(2, colors['white'] if container.bgcolor == color else "transparent")
    preview_row.update()
    if dropdown:
        dropdown.update()


def save_categoria(view, nombre, descripcion, color, activo, cat_id):
    cat_data = {
        "nombre": str(nombre),
        "descripcion": str(descripcion) if descripcion else "",
        "color": str(color),
        "activo": 1 if activo else 0,
        "updated_at": datetime.now().isoformat()
    }
    if cat_id:
        cat_data["id"] = cat_id

    try:
        LocalReplica.save_categorias([cat_data])
    except Exception as e:
        print(f"Error SQLite: {e}")

    try:
        queue = get_sync_queue()
        queue.add_pending('categorias', 'insert', cat_data)
        trigger_sync(view)
    except Exception as e:
        show_error("Error al agregar categoria a cola de sync", e, "configuracion.categorias.save_categoria")

    show_success("Categoria guardada")


def create_categoria_grid(view, categorias):
    colors = _colors(view.page)
    grid_items = []
    for i in range(0, len(categorias), 2):
        row_controls = []
        if i < len(categorias):
            row_controls.append(_create_categoria_card(view, categorias[i]))
        if i + 1 < len(categorias):
            row_controls.append(_create_categoria_card(view, categorias[i + 1]))
        if len(row_controls) == 1:
            row_controls.append(ft.Container(expand=True))
        grid_items.append(ft.Row(row_controls, spacing=15, expand=True))
    return grid_items


def _create_categoria_card(view, c):
    colors = _colors(view.page)
    return ft.Container(
        content=ft.Column([
            ft.Row([
                ft.Container(
                    content=ft.Icon(ft.Icons.CATEGORY, color=colors['white'], size=28),
                    bgcolor=c.color,
                    padding=12,
                    border_radius=12,
                ),
                ft.Column([
                    ft.Text(c.nombre, weight=ft.FontWeight.BOLD, size=15, color=colors['text_primary']),
                    ft.Text(
                        c.descripcion or "Sin descripcion",
                        size=12,
                        color=colors['text_secondary'],
                        max_lines=1,
                        overflow=ft.TextOverflow.ELLIPSIS,
                    ),
                ], expand=True, spacing=2),
            ], alignment=ft.MainAxisAlignment.START),
            ft.Divider(height=1, color=colors['border']),
            ft.Row([
                ft.Container(
                    content=ft.Row([
                        ft.Icon(ft.Icons.CIRCLE, size=8, color=colors['success'] if c.activo else "#9E9E9E"),
                        ft.Text("Activo" if c.activo else "Inactivo", size=11, color=colors['text_secondary']),
                    ], spacing=5),
                ),
                ft.Row([
                    ft.IconButton(
                        ft.Icons.EDIT,
                        icon_size=18,
                        on_click=lambda _, cat=c: show_categoria_dialog(view, cat),
                    ),
                    ft.IconButton(
                        ft.Icons.DELETE,
                        icon_size=18,
                        on_click=lambda _, cat=c: confirm_delete(view, cat, "categoria"),
                    ),
                ], spacing=0),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        ], spacing=10),
        padding=15,
        bgcolor=colors['card'],
        border_radius=15,
        border=ft.border.all(1, colors['border']),
        expand=True,
    )


def create_categoria_item_mobile(view, c):
    colors = _colors(view.page)
    return ft.Container(
        content=ft.Column([
            ft.Row([
                ft.Container(
                    content=ft.Icon(ft.Icons.CATEGORY, color=colors['white'], size=24),
                    bgcolor=c.color,
                    padding=10,
                    border_radius=10,
                ),
                ft.Column([
                    ft.Text(c.nombre, weight=ft.FontWeight.BOLD, size=14, color=colors['text_primary']),
                    ft.Text(
                        c.descripcion or "Sin descripcion",
                        size=11,
                        color=colors['text_secondary'],
                        max_lines=1,
                        overflow=ft.TextOverflow.ELLIPSIS,
                    ),
                ], expand=True, spacing=1),
            ], alignment=ft.MainAxisAlignment.START),
            ft.Row([
                ft.Container(
                    content=ft.Row([
                        ft.Icon(ft.Icons.CIRCLE, size=6, color=colors['success'] if c.activo else "#9E9E9E"),
                        ft.Text("Activo" if c.activo else "Inactivo", size=10, color=colors['text_secondary']),
                    ], spacing=4),
                ),
                ft.Row([
                    ft.IconButton(
                        ft.Icons.EDIT,
                        icon_size=20,
                        padding=5,
                        on_click=lambda _, cat=c: show_categoria_dialog(view, cat),
                    ),
                    ft.IconButton(
                        ft.Icons.DELETE,
                        icon_size=20,
                        padding=5,
                        on_click=lambda _, cat=c: confirm_delete(view, cat, "categoria"),
                    ),
                ], spacing=0),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        ], spacing=8),
        padding=15,
        bgcolor=colors['card'],
        border_radius=12,
        border=ft.border.all(1, colors['border']),
        width=None,
    )
