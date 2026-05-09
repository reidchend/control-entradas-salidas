import flet as ft
from usr.models import Existencia
from usr.database.base import get_db_adaptive
from usr.views.inventario.helpers import get_attr, get_safe_colors


def get_almacenes():
    db = next(get_db_adaptive())
    try:
        almacenes = db.query(Existencia.almacen).distinct().all()
        opciones = [a[0] for a in almacenes]
        if "principal" not in opciones:
            opciones.insert(0, "principal")
        return opciones
    finally:
        db.close()


def create_producto_item(producto, stock_por_almacen, colors, callbacks):
    if stock_por_almacen is None:
        stock_por_almacen = {}
    stock = sum(stock_por_almacen.values()) or 0
    stock_min = getattr(producto, 'stock_minimo', 0) or 0
    stock_color = colors['error'] if stock < stock_min else colors['success']

    es_pesable = getattr(producto, 'es_pesable', False)
    badge_pesable = ft.Container(
        content=ft.Text("PESABLE", size=9, color='#FFFFFF', weight="bold"),
        bgcolor='#FF9800',
        padding=ft.padding.symmetric(horizontal=4, vertical=1),
        border_radius=3
    ) if es_pesable else ft.Container()

    return ft.Container(
        content=ft.Row([
            ft.Column([
                ft.Row([ft.Text(str(producto.nombre), weight="bold", size=14, color=colors['text_primary']), badge_pesable], spacing=5),
                ft.Row([
                    ft.Container(
                        content=ft.Text(f"Stock: {stock}", size=10, weight="bold", color='#FFFFFF'),
                        bgcolor=stock_color, padding=ft.padding.symmetric(horizontal=6, vertical=2), border_radius=5
                    ),
                    ft.Text(f"Mín: {stock_min}", size=10, color=colors['text_secondary']),
                ], spacing=10)
            ], expand=True),
            ft.IconButton(ft.Icons.ADD_CIRCLE_OUTLINE_ROUNDED, icon_color=colors['success'], icon_size=24,
                         on_click=lambda _, p=producto: callbacks.get('on_entrada')(p)),
            ft.IconButton(ft.Icons.REMOVE_CIRCLE_OUTLINE_ROUNDED, icon_color=colors['error'], icon_size=24,
                         on_click=lambda _, p=producto: callbacks.get('on_salida')(p)),
        ], spacing=5),
        padding=10, bgcolor=colors['card'], border_radius=10, border=ft.border.all(1, colors['border'])
    )


def create_producto_item_from_dict(prod_dict, stock_por_almacen, colors, callbacks):
    if stock_por_almacen is None:
        stock_por_almacen = {}
    stock = sum(stock_por_almacen.values()) or 0
    stock_min = prod_dict.get("stock_minimo", 0) or 0
    stock_color = colors['error'] if stock < stock_min else colors['success']

    prod_obj = type('Producto', (), prod_dict)()

    return ft.Container(
        content=ft.Row([
            ft.Column([
                ft.Row([ft.Text(str(prod_dict.get("nombre", "")), weight="bold", size=14, color=colors['text_primary'])], spacing=5),
                ft.Row([
                    ft.Container(
                        content=ft.Text(f"Stock: {stock}", size=10, weight="bold", color='#FFFFFF'),
                        bgcolor=stock_color, padding=ft.padding.symmetric(horizontal=6, vertical=2), border_radius=5
                    ),
                    ft.Text(f"Mín: {stock_min}", size=10, color=colors['text_secondary']),
                ], spacing=10)
            ], expand=True),
            ft.IconButton(ft.Icons.ADD_CIRCLE_OUTLINE_ROUNDED, icon_color=colors['success'], icon_size=24,
                         on_click=lambda _, p=prod_obj: callbacks.get('on_entrada')(p)),
            ft.IconButton(ft.Icons.REMOVE_CIRCLE_OUTLINE_ROUNDED, icon_color=colors['error'], icon_size=24,
                         on_click=lambda _, p=prod_obj: callbacks.get('on_salida')(p)),
        ], spacing=5),
        padding=10, bgcolor=colors['card'], border_radius=10, border=ft.border.all(1, colors['border'])
    )
