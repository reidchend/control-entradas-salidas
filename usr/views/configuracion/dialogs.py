import flet as ft
from datetime import datetime
from usr.database.base import get_db_adaptive
from usr.models import Producto, Categoria
from usr.database.sync_queue import get_sync_queue
from usr.database.local_replica import LocalReplica
from usr.notifications import show_success, show_error
from usr.views.configuracion.helpers import _colors, trigger_sync


def close_dialog(view, e=None):
    if not view.page:
        return
    for control in view.page.overlay[:]:
        if isinstance(control, ft.AlertDialog):
            control.open = False
    if view.active_dialog:
        view.active_dialog.open = False
    view.page.update()
    view.active_dialog = None


def add_to_overlay(view, control):
    if view.page:
        if isinstance(control, ft.AlertDialog):
            control.open = True
            if control not in view.page.overlay:
                view.page.overlay.append(control)
        else:
            if control not in view.page.overlay:
                view.page.overlay.append(control)
        view.page.update()


def remove_from_overlay(view, control):
    if view.page and control in view.page.overlay:
        view.page.overlay.remove(control)


def confirm_delete(view, objeto, tipo="producto"):
    colors = _colors(view.page)
    color = colors['error'] if tipo == "producto" else "#ff9800"

    view.active_dialog = ft.AlertDialog(
        title=ft.Row([
            ft.Icon(ft.Icons.WARNING, color=colors['error']),
            ft.Text(f"Eliminar {tipo.capitalize()}", weight=ft.FontWeight.BOLD),
        ], spacing=10),
        content=ft.Column([
            ft.Text(
                f"¿Está seguro que desea eliminar '{objeto.nombre}'?",
                size=15,
            ),
            ft.Text(
                "Esto lo desactivará del catálogo pero mantendrá el historial.",
                size=12,
                color=colors['text_secondary'],
                italic=True,
            ),
        ], spacing=10),
        actions=[
            ft.TextButton("Cancelar", on_click=lambda e: close_dialog(view, e)),
            ft.ElevatedButton(
                "Eliminar",
                color=colors['white'],
                bgcolor=color,
                on_click=lambda _: delete_logic(view, objeto, tipo),
            ),
        ],
        actions_alignment=ft.MainAxisAlignment.END,
    )
    add_to_overlay(view, view.active_dialog)


def delete_logic(view, objeto, tipo):
    db = next(get_db_adaptive())
    try:
        if tipo == "producto":
            item = db.query(Producto).get(objeto.id)
        else:
            item = db.query(Categoria).get(objeto.id)

        if tipo == "producto":
            item.activo = False
            db.commit()
            LocalReplica.save_productos([{
                'id': item.id,
                'nombre': item.nombre,
                'codigo': item.codigo,
                'descripcion': item.descripcion,
                'categoria_id': item.categoria_id,
                'es_pesable': item.es_pesable,
                'requiere_foto_peso': item.requiere_foto_peso,
                'peso_unitario': item.peso_unitario,
                'unidad_medida': item.unidad_medida,
                'stock_actual': item.stock_actual,
                'stock_minimo': item.stock_minimo,
                'activo': 0,
                'updated_at': datetime.now().isoformat(),
                'almacen_predeterminado': item.almacen_predeterminado
            }])
            try:
                queue = get_sync_queue()
                queue.add_pending('productos', 'update', {
                    'id': item.id,
                    'activo': 0,
                    'updated_at': datetime.now().isoformat()
                })
                trigger_sync(view)
            except:
                pass
        else:
            item.activo = False
            db.commit()
            LocalReplica.save_categorias([{
                'id': item.id,
                'nombre': item.nombre,
                'descripcion': item.descripcion,
                'color': item.color,
                'activo': 0,
                'updated_at': datetime.now().isoformat()
            }])
            try:
                queue = get_sync_queue()
                queue.add_pending('categorias', 'update', {
                    'id': item.id,
                    'activo': 0,
                    'updated_at': datetime.now().isoformat()
                })
                trigger_sync(view)
            except Exception as e:
                from usr.error_handler import show_error
                show_error("Error al actualizar categoría en cola de sync", e, "configuracion.dialogs._toggle_categoria")

        show_success(f"{tipo.capitalize()} desactivado correctamente")
        view._load_data()
        close_dialog(view)
    except Exception as e:
        show_error(f"Error: {str(e)}")
    finally:
        db.close()



