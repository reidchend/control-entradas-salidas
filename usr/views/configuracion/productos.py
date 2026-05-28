import flet as ft
from datetime import datetime
from usr.database.base import get_db_adaptive
from usr.models import Categoria, Producto
from usr.database.sync_queue import get_sync_queue
from usr.database.local_replica import LocalReplica
from usr.notifications import show_success, show_error as show_error_notif, show_warning
from usr.views.configuracion.helpers import _colors, trigger_sync
from usr.views.configuracion.dialogs import close_dialog, add_to_overlay, confirm_delete


def show_producto_dialog(view, producto=None):
    colors = _colors(view.page)
    db = next(get_db_adaptive())
    try:
        categorias = db.query(Categoria).filter(Categoria.activo == True).all()
        if not categorias:
            show_warning("Cree al menos una categoria")
            return

        nuevo_codigo = ""
        if not producto:
            try:
                todos_productos = db.query(Producto).filter(Producto.activo == True).all()
                codigos_numericos = []
                for p in todos_productos:
                    if p.codigo and str(p.codigo).strip().isdigit():
                        codigos_numericos.append(int(p.codigo))
                if codigos_numericos:
                    ultimo_numero = max(codigos_numericos)
                    siguiente_numero = ultimo_numero + 1
                    longitud = 4
                    for p in todos_productos:
                        if p.codigo and str(p.codigo).strip().isdigit():
                            longitud = max(longitud, len(str(p.codigo)))
                    nuevo_codigo = str(siguiente_numero).zfill(longitud)
                else:
                    nuevo_codigo = "0001"
            except Exception as ex:
                from usr.error_handler import show_error
                show_error("Error generating code", ex, "configuracion.productos.show_producto_dialog")
                nuevo_codigo = "0001"
        else:
            nuevo_codigo = producto.codigo

        is_mobile = view.page.width < 600

        nombre_field = ft.TextField(
            label="Nombre",
            value=producto.nombre if producto else "",
            expand=True,
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            prefix_icon=ft.Icons.INVENTORY_2,
            capitalization=ft.TextCapitalization.WORDS,
        )

        codigo_field = ft.TextField(
            label="Codigo",
            value=nuevo_codigo,
            expand=True,
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            prefix_icon=ft.Icons.QR_CODE,
            helper_text="Auto" if not producto else "",
            read_only=not producto,
        )

        cat_options = [ft.dropdown.Option(str(c.id), c.nombre) for c in categorias]
        cat_dropdown = ft.Dropdown(
            label="Categoria",
            options=cat_options,
            value=str(producto.categoria_id) if producto else str(categorias[0].id),
            expand=True,
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            prefix_icon=ft.Icons.CATEGORY,
        )

        stock_min_field = ft.TextField(
            label="Stock Min.",
            value=str(producto.stock_minimo) if producto else "5",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True,
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            prefix_icon=ft.Icons.WARNING,
        )

        unidad_field = ft.TextField(
            label="Unidad",
            value=producto.unidad_medida if producto else "unidad",
            expand=True,
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            prefix_icon=ft.Icons.SCALE,
        )

        tipo_options = [
            ft.dropdown.Option("feria"),
            ft.dropdown.Option("productos para uso Interno"),
            ft.dropdown.Option("Productos para la venta"),
            ft.dropdown.Option("ninguno"),
        ]
        tipo_dropdown = ft.Dropdown(
            label="Tipo",
            options=tipo_options,
            value=getattr(producto, 'tipo', 'ninguno') if producto else "ninguno",
            expand=True,
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            prefix_icon=ft.Icons.TAG,
        )

        descripcion_field = ft.TextField(
            label="Descripcion",
            value=producto.descripcion if producto else "",
            multiline=True,
            max_length=500,
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            min_lines=2,
            max_lines=4,
            prefix_icon=ft.Icons.DESCRIPTION,
        )

        es_pesable_sw = ft.Switch(
            label="Usa balanza",
            value=getattr(producto, 'es_pesable', False) if producto else False,
            active_color=colors['warning'],
        )

        peso_unitario_field = ft.TextField(
            label="Peso unitario (kg)",
            value=str(getattr(producto, 'peso_unitario', 0) or 0) if producto else "0",
            keyboard_type=ft.KeyboardType.NUMBER,
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            prefix_text="kg  ",
            visible=es_pesable_sw.value,
        )

        requiere_foto_sw = ft.Switch(
            label="Requiere foto del peso",
            value=getattr(producto, 'requiere_foto_peso', False) if producto else False,
            active_color=colors['warning'],
            visible=es_pesable_sw.value,
        )

        def _toggle_pesable_fields(e):
            visible = es_pesable_sw.value
            peso_unitario_field.visible = visible
            requiere_foto_sw.visible = visible
            view.update()

        es_pesable_sw.on_change = _toggle_pesable_fields

        almacen_options = [
            ft.dropdown.Option("principal", "Principal"),
            ft.dropdown.Option("restaurante", "Restaurante"),
        ]
        almacen_dropdown = ft.Dropdown(
            label="Almacen predeterminado",
            options=almacen_options,
            value=getattr(producto, 'almacen_predeterminado', 'principal') if producto else "principal",
            expand=True,
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            prefix_icon=ft.Icons.WAREHOUSE,
        )

        activo_sw = ft.Switch(
            label="Habilitado",
            value=producto.activo if producto else True,
            active_color=colors['success'],
        )

        def save_prod_click(e):
            if not nombre_field.value or not nombre_field.value.strip():
                nombre_field.error_text = "Requerido"
                nombre_field.update()
                return
            if not codigo_field.value or not codigo_field.value.strip():
                codigo_field.error_text = "Requerido"
                codigo_field.update()
                return
            try:
                save_producto(
                    view,
                    nombre_field.value.strip(),
                    codigo_field.value.strip(),
                    descripcion_field.value.strip() if descripcion_field.value else "",
                    int(cat_dropdown.value),
                    requiere_foto_sw.value,
                    float(peso_unitario_field.value or 0),
                    unidad_field.value.strip(),
                    float(stock_min_field.value or 0),
                    activo_sw.value,
                    producto.id if producto else None,
                    es_pesable_sw.value,
                    almacen_dropdown.value,
                    tipo_dropdown.value,
                    )
            except Exception as ex:
                from usr.error_handler import show_error
                show_error("Error saving product", ex, "configuracion.productos.save_prod_click")
                show_error_notif(f"Error: {str(ex)}")

        def _pesable_divider():
            return ft.Divider(height=15 if is_mobile else 20, color=colors['warning'])

        if is_mobile:
            content_column = ft.Column([
                nombre_field,
                codigo_field,
                cat_dropdown,
                stock_min_field,
                unidad_field,
        descripcion_field,
        ft.Divider(height=15, color=colors['border']),
        es_pesable_sw,
        peso_unitario_field,
        requiere_foto_sw,
        ft.Divider(height=15, color=colors['border']),
        tipo_dropdown,
        ft.Divider(height=15, color=colors['border']),
        almacen_dropdown,
                activo_sw,
            ], spacing=12, tight=True, scroll=ft.ScrollMode.AUTO)
        else:
            content_column = ft.Column([
                ft.Row([nombre_field, codigo_field], spacing=15),
                cat_dropdown,
                ft.Row([stock_min_field, unidad_field], spacing=15),
                descripcion_field,
                ft.Divider(height=20, color=colors['border']),
                es_pesable_sw,
                peso_unitario_field,
                requiere_foto_sw,
                ft.Divider(height=20, color=colors['border']),
                almacen_dropdown,
                activo_sw,
            ], spacing=15, tight=True, scroll=ft.ScrollMode.AUTO)

        view.active_dialog = ft.AlertDialog(
            title=ft.Row([
                ft.Icon(ft.Icons.INVENTORY_2, color=colors['success'], size=24 if is_mobile else 28),
                ft.Text(
                    "Producto" if is_mobile else "Ficha de Producto",
                    weight=ft.FontWeight.BOLD,
                    size=16 if is_mobile else 18,
                ),
            ], spacing=8),
            content=ft.Container(
                content=content_column,
                width=None if is_mobile else 550,
                padding=5,
            ),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda e: close_dialog(view, e)),
                ft.ElevatedButton(
                    "Guardar",
                    on_click=save_prod_click,
                    bgcolor=colors['success'],
                    color=colors['white'],
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        add_to_overlay(view, view.active_dialog)
    finally:
        db.close()


def save_producto(view, n, c, d, cat_id, rf, pu, u, sm, a, p_id, es_p=False, almacen="principal", tipo="ninguno"):
    stock_actual_val = 0
    if p_id:
        existing = LocalReplica.get_producto_by_id(p_id)
        if existing:
            stock_actual_val = existing.get("stock_actual", 0) if isinstance(existing, dict) else getattr(existing, "stock_actual", 0)

    prod_data = {
        "nombre": str(n),
        "codigo": str(c),
        "descripcion": str(d) if d else "",
        "categoria_id": int(cat_id) if cat_id else None,
        "requiere_foto_peso": 1 if rf else 0,
        "peso_unitario": float(pu) if pu else 0.0,
        "stock_minimo": float(sm) if sm else 0.0,
        "stock_actual": stock_actual_val,
        "unidad_medida": str(u) if u else "unidad",
        "activo": 1 if a else 0,
        "es_pesable": 1 if es_p else 0,
        "almacen_predeterminado": str(almacen) if almacen else "principal",
        "tipo": tipo,
        "updated_at": datetime.now().isoformat()
    }
    if p_id:
        prod_data["id"] = p_id

    try:
        LocalReplica.save_productos([prod_data])
    except Exception as e:
        print(f"Error SQLite: {e}")

    try:
        queue = get_sync_queue()
        queue.add_pending('productos', 'insert', prod_data)
        trigger_sync(view)
    except:
        pass

    show_success("Guardado")
    close_dialog(view)
    if callable(getattr(view, '_load_data', None)):
        view._load_data()
    return True


def create_producto_item(view, p):
    colors = _colors(view.page)
    tag = ft.Container(
        content=ft.Text("PESABLE", size=9, weight=ft.FontWeight.BOLD, color=colors['white']),
        bgcolor=colors['warning'],
        padding=ft.padding.symmetric(horizontal=6, vertical=2),
        border_radius=4,
    ) if getattr(p, 'es_pesable', False) else None

    descripcion = getattr(p, 'descripcion', None) or ''
    desc_text = ft.Text(
        descripcion, size=11, color=colors['text_secondary'],
        max_lines=1, overflow=ft.TextOverflow.ELLIPSIS,
    ) if descripcion else ft.Container()

    alm_txt = getattr(p, 'almacen_predeterminado', 'principal') or 'principal'
    almacen_badge = ft.Container(
        content=ft.Text(alm_txt.upper(), size=9, color=colors['white'], weight=ft.FontWeight.BOLD),
        bgcolor=colors['accent_dark'],
        padding=ft.padding.symmetric(horizontal=6, vertical=2),
        border_radius=4,
    )

    tipo_txt = getattr(p, 'tipo', 'ninguno') or 'ninguno'
    tipo_badge = ft.Container(
        content=ft.Text(tipo_txt.upper(), size=9, color=colors['white'], weight=ft.FontWeight.BOLD),
        bgcolor=colors.get('warning' if tipo_txt.lower() == 'feria' else 'secondary'),
        padding=ft.padding.symmetric(horizontal=6, vertical=2),
        border_radius=4,
    )

    return ft.Container(
        content=ft.Column([
            ft.Row([
                ft.Container(
                    content=ft.Icon(ft.Icons.INVENTORY_2, color=colors['white'], size=24),
                    bgcolor=colors['accent'],
                    padding=10,
                    border_radius=10,
                ),
                ft.Column([
                    ft.Row([
                        ft.Text(p.nombre, weight=ft.FontWeight.BOLD, size=14, color=colors['text_primary']),
                        tag if tag else ft.Container(),
                    ], spacing=8),
                    ft.Text(
                        f"Cat: {p.categoria.nombre if p.categoria else 'N/A'}  SKU: {p.codigo}",
                        size=11,
                        color=colors['text_secondary'],
                    ),
                    desc_text,
                ], expand=True, spacing=2),
                almacen_badge,
                tipo_badge,
            ], alignment=ft.MainAxisAlignment.START),
            ft.Row([
                ft.Row([
                    ft.Icon(ft.Icons.LIST, size=14, color=colors['text_secondary']),
                    ft.Text(f"Min: {p.stock_minimo} {p.unidad_medida}", size=11, color=colors['text_secondary']),
                ], spacing=5),
                ft.Row([
                    ft.IconButton(
                        ft.Icons.EDIT,
                        icon_size=18,
                        on_click=lambda _, prod=p: show_producto_dialog(view, prod),
                    ),
                    ft.IconButton(
                        ft.Icons.DELETE,
                        icon_size=18,
                        on_click=lambda _, prod=p: confirm_delete(view, prod, "producto"),
                    ),
                ], spacing=0),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        ], spacing=8),
        padding=12,
        bgcolor=colors['card'],
        border_radius=12,
        border=ft.border.all(1, colors['border']),
    )
