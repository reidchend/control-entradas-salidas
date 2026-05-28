import flet as ft
from datetime import datetime
from usr.database.sync_queue import get_sync_queue
from usr.database.local_replica import LocalReplica
from usr.notifications import show_error
from usr.views.configuracion.helpers import _colors, trigger_sync


def show_proveedor_dialog(view, proveedor=None):
    colors = _colors(view.page)

    nombre_input = ft.TextField(
        label="Nombre *",
        value=proveedor.get('nombre', '') if proveedor else '',
        border_radius=10
    )
    rif_input = ft.TextField(
        label="RIF",
        value=proveedor.get('rif', '') if proveedor else '',
        border_radius=10
    )
    telefono_input = ft.TextField(
        label="Telefono",
        value=proveedor.get('telefono', '') if proveedor else '',
        border_radius=10
    )
    email_input = ft.TextField(
        label="Email",
        value=proveedor.get('email', '') if proveedor else '',
        border_radius=10
    )
    direccion_input = ft.TextField(
        label="Direccion",
        value=proveedor.get('direccion', '') if proveedor else '',
        border_radius=10,
        multiline=True,
        min_lines=2
    )
    contacto_input = ft.TextField(
        label="Persona de contacto",
        value=proveedor.get('contacto', '') if proveedor else '',
        border_radius=10
    )
    observaciones_input = ft.TextField(
        label="Observaciones",
        value=proveedor.get('observaciones', '') if proveedor else '',
        border_radius=10,
        multiline=True,
        min_lines=2
    )
    estado_switch = ft.Switch(
        label="Activo",
        value=proveedor.get('estado', 'Activo') == 'Activo' if proveedor else True,
    )

    prov_id = proveedor.get('id') if proveedor else None

    from usr.views.configuracion.dialogs import close_dialog
    def on_guardar(e):
        if not nombre_input.value.strip():
            return
        save_proveedor(
            view,
            nombre_input.value.strip(),
            rif_input.value.strip(),
            telefono_input.value.strip(),
            email_input.value.strip(),
            direccion_input.value.strip(),
            contacto_input.value.strip(),
            observaciones_input.value.strip(),
            estado_switch.value,
            prov_id
        )

    view.active_dialog = ft.AlertDialog(
        title=ft.Text(f"{'Editar' if proveedor else 'Nuevo'} Proveedor"),
        content=ft.Column([
            nombre_input, rif_input, telefono_input, email_input,
            direccion_input, contacto_input, observaciones_input, estado_switch
        ], tight=True, scroll=ft.ScrollMode.AUTO),
        actions=[
            ft.TextButton("Cancelar", on_click=lambda e: close_dialog(view, e)),
            ft.ElevatedButton("Guardar", on_click=on_guardar, bgcolor=colors['accent']),
        ]
    )
    view.page.overlay.append(view.active_dialog)
    view.active_dialog.open = True
    view.page.update()


def save_proveedor(view, nombre, rif, telefono, email, direccion, contacto, observaciones, activo, prov_id):
    prov_data = {
        "nombre": str(nombre),
        "rif": str(rif) if rif else None,
        "telefono": str(telefono) if telefono else None,
        "email": str(email) if email else None,
        "direccion": str(direccion) if direccion else None,
        "contacto": str(contacto) if contacto else None,
        "observaciones": str(observaciones) if observaciones else None,
        "estado": "Activo" if activo else "Inactivo",
        "updated_at": datetime.now().isoformat()
    }
    if prov_id:
        prov_data["id"] = prov_id

    try:
        LocalReplica.save_proveedores([prov_data])
    except Exception as e:
        print(f"Error SQLite: {e}")

    try:
        queue = get_sync_queue()
        queue.add_pending('proveedores', 'insert', prov_data)
        trigger_sync(view)
    except Exception as e:
        show_error("Error al agregar proveedor a sync", e, "configuracion.proveedores.save_proveedor")


def load_proveedores(view):
    view.proveedores_data = LocalReplica.get_proveedores()
    render_proveedores(view, view.proveedores_data)


def render_proveedores(view, data):
    colors = _colors(view.page)
    view.lista_proveedores.controls = []

    for prov in data:
        card = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Icon(ft.Icons.LOCAL_SHIPPING, color=colors['accent']),
                    ft.Text(prov.get('nombre', 'Sin nombre'), weight="bold", expand=True),
                    ft.Container(
                        content=ft.Text(prov.get('estado', 'Activo'), size=10, color="white"),
                        bgcolor=colors['success'] if prov.get('estado') == 'Activo' else colors['error'],
                        padding=ft.padding.symmetric(horizontal=8, vertical=2),
                        border_radius=10
                    )
                ]),
                ft.Divider(height=10),
                ft.Text(prov.get('rif', 'Sin RIF'), size=11, color=colors['text_secondary']),
                ft.Text(prov.get('telefono', 'Sin telefono'), size=11, color=colors['text_secondary']),
                ft.Text(prov.get('email', 'Sin email'), size=11, color=colors['text_secondary']),
            ], spacing=2),
            padding=15,
            bgcolor=colors['card'],
            border_radius=10,
            ink=True,
            on_click=lambda _, p=prov: show_proveedor_dialog(view, p)
        )
        view.lista_proveedores.controls.append(card)

    view.page.update()


def filter_proveedores(view, e):
    search = view.proveedor_search.value.lower()
    if not search:
        render_proveedores(view, view.proveedores_data)
        return
    filtered = [p for p in view.proveedores_data
                if search in (p.get('nombre') or '').lower()
                or search in (p.get('rif') or '').lower()]
    render_proveedores(view, filtered)


def build_proveedores_tab(view):
    colors = _colors(view.page)
    fab_content = ft.Row([
        ft.Icon(ft.Icons.ADD, size=20),
        ft.Text("Nuevo Proveedor" if not view.is_mobile else "Nuevo", weight=ft.FontWeight.BOLD),
    ], alignment=ft.MainAxisAlignment.CENTER, spacing=8)

    view.proveedor_search = ft.TextField(
        hint_text="Buscar proveedores...",
        prefix_icon=ft.Icons.SEARCH,
        border_radius=10,
        bgcolor=colors['card'],
        border_color=colors['border'],
        height=40,
        expand=True,
        on_change=lambda e: filter_proveedores(view, e),
    )

    view.lista_proveedores = ft.GridView(
        expand=True,
        runs_count=1 if view.is_mobile else 3,
        spacing=10,
        padding=20,
    )

    return ft.Container(
        content=ft.Column([
            ft.Container(height=15),
            ft.Row([
                view.proveedor_search,
                ft.Container(
                    content=fab_content,
                    bgcolor=colors['accent'],
                    padding=ft.padding.symmetric(horizontal=20, vertical=12),
                    border_radius=30,
                    on_click=lambda _: show_proveedor_dialog(view),
                ),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN, spacing=10),
            ft.Container(height=15),
            view.lista_proveedores,
        ], expand=True, spacing=0),
        padding=20,
        expand=True,
    )
