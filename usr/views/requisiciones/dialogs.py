import flet as ft
from datetime import datetime

from usr.database.base import get_db_adaptive
from usr.models import Producto, Existencia
from usr.views.requisiciones.helpers import _colors, _c
from usr.views.requisiciones.data import (
    get_almacenes, get_productos_activos, get_detalles, buscar_productos, guardar_requisicion
)
from usr.views.requisiciones.components import build_producto_busqueda_item


def build_crear_dialog(view):
    """Diálogo 'Nueva Requisición' (flujo antiguo): crea con estado 'completada'
    y transfiere existencias origen->destino de inmediato."""
    colors = _colors(view.page)
    is_mobile = view.page.width < 700 if view.page else False
    view.detalles_temp = []

    almacenes = get_almacenes()
    productos = get_productos_activos(limit=200)
    view._productos_cache = productos

    origen_dropdown = ft.Dropdown(
        label="Origen",
        options=[ft.dropdown.Option(a, a.title()) for a in almacenes],
        value="principal",
        border_radius=10,
        expand=True,
    )

    destino_dropdown = ft.Dropdown(
        label="Destino",
        options=[ft.dropdown.Option(a, a.title()) for a in almacenes],
        value="restaurante",
        border_radius=10,
        expand=True,
    )

    observaciones_input = ft.TextField(
        label="Observaciones",
        hint_text="Notas...",
        border_radius=10,
        multiline=True,
        min_lines=2,
    )

    productos_container = ft.Column([], spacing=5)
    view._productos_container = productos_container

    busqueda_input = ft.TextField(
        hint_text="Buscar producto...",
        prefix_icon=ft.Icons.SEARCH,
        border_radius=12,
        on_change=lambda e: view._filtrar_productos_busqueda(e.control.value, view._productos_cache, resultados_container, agregar_producto_rapido),
    )

    resultados_container = ft.Column([], spacing=5)
    view._resultados_container = resultados_container

    def agregar_producto_rapido(producto, cantidad, peso=0):
        for fila in productos_container.controls:
            prod_label = fila.controls[0]
            if hasattr(prod_label, 'producto_id') and prod_label.producto_id == producto.id:
                cant_input = fila.controls[1]
                try:
                    cant_input.value = str(float(cant_input.value or "0") + cantidad)
                    cant_input.update()
                except Exception:
                    pass
                return

        es_pesable = getattr(producto, 'es_pesable', False)

        cant_input = ft.TextField(
            value=str(cantidad),
            keyboard_type=ft.KeyboardType.NUMBER,
            border_radius=10,
            width=80,
        )

        peso_input = ft.TextField(
            value=str(peso) if es_pesable else "0",
            keyboard_type=ft.KeyboardType.NUMBER,
            border_radius=10,
            width=80,
            visible=es_pesable,
        )

        prod_label = ft.Text(
            producto.nombre,
            size=14,
            weight="bold",
            color=colors['text_primary'],
        )
        prod_label.producto_id = producto.id

        unit_text = ft.Text(
            producto.unidad_medida or "uds",
            size=12,
            color=colors['text_secondary'],
        )

        delete_btn = ft.IconButton(
            ft.Icons.DELETE_ROUNDED,
            icon_color=colors['error'],
            on_click=lambda _, pl=prod_label: view._eliminar_producto_row(pl, productos_container)
        )

        if es_pesable:
            fila = ft.Row([
                prod_label,
                cant_input,
                unit_text,
                peso_input,
                ft.Text("kg", size=12, color=colors['text_secondary']),
                delete_btn,
            ], spacing=5)
        else:
            fila = ft.Row([
                prod_label,
                cant_input,
                unit_text,
                delete_btn,
            ], spacing=5)

        productos_container.controls.append(fila)
        productos_container.update()

    view._agregar_producto_req = agregar_producto_rapido

    agregar_btn = ft.ElevatedButton(
        "Agregar",
        icon=ft.Icons.ADD,
        on_click=lambda _: view._show_agregar_producto_dialog(productos_container),
    )

    def on_confirmar(e):
        if not productos_container.controls:
            from usr.notifications import show_warning
            show_warning("Agregue al menos un producto")
            return

        detalles = []
        origen = origen_dropdown.value or "principal"
        destino = destino_dropdown.value or "restaurante"

        for fila in productos_container.controls:
            prod_label = fila.controls[0]
            cant_input = fila.controls[1]
            unidad_text = fila.controls[2]

            producto_id = getattr(prod_label, 'producto_id', None)
            if producto_id and cant_input.value:
                try:
                    cantidad = float(cant_input.value.replace(",", ""))
                    peso = 0
                    if len(fila.controls) > 3:
                        peso = float(fila.controls[3].value or "0")

                    producto = None
                    try:
                        from usr.database.base import get_db_adaptive
                        from usr.models import Producto
                        dbp = next(get_db_adaptive())
                        try:
                            producto = dbp.query(Producto).filter(Producto.id == producto_id).first()
                        finally:
                            dbp.close()
                    except Exception:
                        producto = None

                    detalles.append({
                        "producto_id": producto_id,
                        "ingrediente": producto.nombre if producto else "Desconocido",
                        "cantidad": cantidad,
                        "peso": peso,
                        "unidad": unidad_text.value if hasattr(unidad_text, 'value') else str(unidad_text),
                    })
                except ValueError:
                    pass

        user_id = (view.page.session.get("user_id") or "Admin") if view.page else "Admin"
        guardar_requisicion(
            origen=origen, destino=destino,
            observaciones=observaciones_input.value or "",
            detalles=detalles, editando=None, user_id=user_id,
            estado="completada", mover_stock=True,
        )
        view.active_dialog.open = False
        view.page.update()
        view._load_requisiciones()
        from usr.notifications import show_success
        show_success(f"{origen} → {destino}")

    almacenes_row = ft.Container(
        content=ft.Row([
            ft.Column([ft.Text("De", size=11, color=colors['text_secondary']), origen_dropdown], expand=True),
            ft.Icon(ft.Icons.ARROW_FORWARD, color=colors['text_secondary'], size=20),
            ft.Column([ft.Text("A", size=11, color=colors['text_secondary']), destino_dropdown], expand=True),
        ], spacing=10),
        padding=10,
        bgcolor=colors['card'],
        border_radius=10,
    )

    panel_productos = ft.Container(
        content=ft.Column([
            ft.Row([
                ft.Text("Productos", weight="bold", size=14, color=colors['text_primary']),
                ft.Container(expand=True),
                agregar_btn,
            ]),
            ft.Row([
                ft.Container(content=busqueda_input, expand=True),
            ], spacing=5),
            ft.Container(
                content=productos_container,
                bgcolor=colors['bg'],
                border_radius=10,
                height=200,
            ),
        ], spacing=5),
        padding=10,
        bgcolor=colors['card'],
        border_radius=10,
    )

    contenido = ft.Column([
        almacenes_row,
        panel_productos,
        observaciones_input,
    ], spacing=10, tight=True, scroll=ft.ScrollMode.AUTO)

    view.active_dialog = ft.AlertDialog(
        title=ft.Text("Nueva Requisición", weight="bold"),
        content=ft.Container(
            content=contenido,
            width=450 if not is_mobile else None,
        ),
        actions=[
            ft.TextButton("Cancelar", on_click=lambda _: view._close_dialog()),
            ft.ElevatedButton("Crear", on_click=on_confirmar, bgcolor=colors['success'], color="white"),
        ],
    )
    view.page.overlay.append(view.active_dialog)
    view.active_dialog.open = True
    view.page.update()


def build_agregar_producto_dialog(view, productos_container):
    colors = _colors(view.page)
    productos = get_productos_activos(limit=200)

    resultados_container = ft.Column([], spacing=5, scroll=ft.ScrollMode.AUTO)

    busqueda_input = ft.TextField(
        label="Buscar producto",
        hint_text="Escribe el nombre del producto...",
        border_radius=10,
        prefix_icon=ft.Icons.SEARCH,
        autofocus=True,
        on_change=lambda e: view._filtrar_productos_busqueda(e.control.value, productos, resultados_container, agregar_producto),
    )

    def agregar_producto(producto):
        cantidad_input = ft.TextField(
            label="Cantidad",
            value="1",
            keyboard_type=ft.KeyboardType.NUMBER,
            border_radius=10,
            width=100,
        )

        unidad_input = ft.TextField(
            label="Unidad",
            value=producto.unidad_medida or "unidad",
            border_radius=10,
            width=100,
        )

        prod_label = ft.Text(
            producto.nombre,
            size=14,
            expand=True,
        )

        delete_btn = ft.IconButton(
            ft.Icons.DELETE_ROUNDED,
            icon_color=colors['error'],
        )

        fila = ft.Row([
            prod_label,
            cantidad_input,
            unidad_input,
            delete_btn,
        ], spacing=10)

        def eliminar():
            productos_container.controls.remove(fila)
            productos_container.update()

        delete_btn.on_click = lambda _, dbtn=delete_btn: eliminar()

        productos_container.controls.append(fila)
        productos_container.update()

        dialog.open = False
        view.page.update()

    lista_productos = ft.Column([
        build_producto_busqueda_item(p, agregar_producto, colors) for p in productos[:20]
    ], spacing=5, scroll=ft.ScrollMode.AUTO)

    resultados_container.content = lista_productos

    dialog = ft.AlertDialog(
        title=ft.Text("Agregar Producto"),
        content=ft.Column([
            busqueda_input,
            ft.Container(height=10),
            ft.Container(
                content=resultados_container,
                bgcolor=colors['card'],
                border_radius=10,
                border=ft.border.all(1, _c(view.page, 'GREY_300')),
                padding=5,
            ),
        ], tight=True, scroll=ft.ScrollMode.AUTO),
        actions=[
            ft.TextButton("Cerrar", on_click=lambda _: view._cerrar_dialog(dialog)),
        ],
    )

    view.page.overlay.append(dialog)
    dialog.open = True
    view.page.update()


def build_detalles_dialog(view, req):
    colors = _colors(view.page)
    detalles = get_detalles(req.id)

    from usr.views.requisiciones.components import build_detalle_row
    content = ft.Column(spacing=8, scroll=ft.ScrollMode.AUTO)
    for d in detalles:
        content.controls.append(build_detalle_row(d, colors))

    if not detalles:
        content.controls.append(
            ft.Text("No hay productos en esta requisición", color=colors['text_secondary'])
        )

    dialog = ft.AlertDialog(
        title=ft.Text(f"Requisición #{req.numero}"),
        content=ft.Column([
            ft.Row([
                ft.Container(
                    content=ft.Column([
                        ft.Text("Origen", size=11, color=colors['text_secondary']),
                        ft.Text(req.origen.capitalize(), weight="bold"),
                    ], spacing=2),
                ),
                ft.Icon(ft.Icons.ARROW_FORWARD, color=_c(view.page, 'GREY_400')),
                ft.Container(
                    content=ft.Column([
                        ft.Text("Destino", size=11, color=colors['text_secondary']),
                        ft.Text(req.destino.capitalize(), weight="bold"),
                    ], spacing=2),
                ),
            ], spacing=20),
            ft.Divider(),
            ft.Text("Productos:", weight="bold"),
            content,
            ft.Divider(),
            ft.Text(f"Estado: {req.estado.upper()}", weight="bold", color=colors['accent']),
            ft.Text(f"Creada: {req.fecha_creacion.strftime('%d/%m/%Y %H:%M') if req.fecha_creacion else '-'}", size=11, color=colors['text_secondary']),
            ft.Text(f"Observaciones: {req.observaciones or 'Sin observaciones'}", size=11, color=colors['text_secondary']),
        ], tight=True, spacing=10),
        actions=[
            ft.TextButton("Cerrar", on_click=lambda _: view._close_dialog()),
        ],
    )

    view.active_dialog = dialog
    view.page.overlay.append(dialog)
    dialog.open = True
    view.page.update()


def build_crear_vista(view, requisicion=None):
    """Vista de pantalla completa para crear/editar requisición (flujo principal)."""
    colors = _colors(view.page)
    view._vista_actual = "crear"
    view._requisicion_editando = requisicion

    if requisicion:
        view.lista_productos_req = [
            {'producto_id': d.producto_id, 'nombre': d.ingrediente, 'cantidad': d.cantidad, 'unidad': d.unidad}
            for d in requisicion.detalles
        ]
    else:
        view.lista_productos_req = []

    almacenes = get_almacenes()

    origen_val = requisicion.origen if requisicion else "principal"
    destino_val = requisicion.destino if requisicion else "restaurante"

    origen_dropdown = ft.Dropdown(
        label="Desde",
        options=[ft.dropdown.Option(a, a.title()) for a in almacenes],
        value=origen_val,
        border_radius=10,
        expand=True,
    )
    view._origen_dropdown = origen_dropdown

    destino_dropdown = ft.Dropdown(
        label="Hacia",
        options=[ft.dropdown.Option(a, a.title()) for a in almacenes],
        value=destino_val,
        border_radius=10,
        expand=True,
    )

    almacenes_card = ft.Container(
        content=ft.Column([
            ft.Row([
                ft.Icon(ft.Icons.LOCATION_ON_OUTLINED, color=colors['accent'], size=20),
                ft.Text("Ruta de Traslado", weight="bold", size=14, color=colors['text_primary']),
            ], spacing=10),
            ft.Divider(height=5),
            ft.Row([
                ft.Column([ft.Text("Desde", size=11, color=colors['text_secondary']), origen_dropdown], expand=True),
                ft.Icon(ft.Icons.ARROW_FORWARD, color=colors['text_secondary']),
                ft.Column([ft.Text("Hacia", size=11, color=colors['text_secondary']), destino_dropdown], expand=True),
            ], spacing=10),
        ], spacing=5),
        padding=12,
        bgcolor=colors['card'],
        border_radius=12,
    )

    observaciones_input = ft.TextField(
        label="Observaciones",
        hint_text="Notas de la requisición...",
        border_radius=10,
        multiline=True,
        min_lines=1,
        value=requisicion.observaciones if requisicion else "",
    )

    # --- Área de chat: productos agregados como burbujas ---
    chat_area = ft.ListView(
        expand=True,
        spacing=4,
        padding=10,
    )
    view._productos_lista_req = chat_area

    # --- Popup de sugerencias al escribir en el composer ---
    resultados_list = ft.ListView(spacing=5, padding=5, controls=[], expand=True)
    results_panel = ft.Container(
        content=resultados_list,
        bgcolor=colors['surface'],
        border_radius=12,
        border=ft.border.all(1, colors['border']),
        padding=5,
        height=260,
        visible=False,
    )

    def hide_popup():
        results_panel.visible = False
        results_panel.update()

    def on_suggestion_add(producto):
        hide_popup()
        composer_search.value = ""
        composer_search.update()
        view._agregar_producto_req(producto)

    def on_composer_type(e):
        texto = (e.control.value or "").strip()
        if not texto:
            hide_popup()
            return
        db = next(get_db_adaptive())
        try:
            q = db.query(Producto).filter(
                Producto.activo == True,
                Producto.nombre.ilike(f"%{texto}%"),
            ).limit(20).all()
        finally:
            db.close()
        resultados_list.controls.clear()
        for p in q:
            resultados_list.controls.append(
                build_producto_busqueda_item(p, on_suggestion_add, colors)
            )
        results_panel.visible = True
        results_panel.update()

    composer_search = ft.TextField(
        hint_text="Escribe un producto...",
        prefix_icon=ft.Icons.SEARCH,
        border_radius=24,
        filled=True,
        fill_color=colors['card'],
        on_change=on_composer_type,
        expand=True,
    )

    add_btn = ft.IconButton(
        ft.Icons.ADD_CIRCLE,
        icon_color=colors['accent'],
        icon_size=32,
        tooltip="Buscar y agregar",
        on_click=lambda _: view._abrir_buscador_productos(),
    )

    composer = ft.Container(
        content=ft.Row([
            composer_search,
            add_btn,
        ], spacing=8, vertical_alignment="center"),
        padding=ft.padding.symmetric(horizontal=10, vertical=8),
        bgcolor=colors['surface'],
        border=ft.border.only(top=ft.border.BorderSide(1, colors['border'])),
    )

    titulo = "Editar Requisición" if requisicion else "Nueva Requisición"
    btn_texto = "Actualizar" if requisicion else "Crear"
    btn_color = colors['accent'] if requisicion else colors['success']

    header = ft.Container(
        content=ft.Row([
            ft.IconButton(
                ft.Icons.ARROW_BACK,
                on_click=lambda _: view._volver_lista(),
            ),
            ft.Text(titulo, size=18, weight="bold", color=colors['text_primary']),
            ft.Container(expand=True),
            ft.ElevatedButton(
                btn_texto,
                on_click=lambda _: view._crear_requisicion_vista(origen_dropdown, destino_dropdown, observaciones_input),
                bgcolor=btn_color,
                color="white",
            ),
        ], spacing=10),
        padding=ft.padding.symmetric(horizontal=10, vertical=8),
        bgcolor=colors['surface'],
    )

    scroll_body = ft.Container(
        content=ft.Column([
            almacenes_card,
            observaciones_input,
            chat_area,
            results_panel,
        ], spacing=10, expand=True, scroll=ft.ScrollMode.AUTO),
        padding=10,
        expand=True,
    )

    view._vista_crear = ft.Container(
        content=ft.Column([
            header,
            scroll_body,
            composer,
        ], spacing=0, expand=True),
        bgcolor=colors['bg'],
        padding=0,
    )

    view.content = view._vista_crear
    view.update()
    view._actualizar_lista_productos()


def build_buscador_productos(view):
    """BottomSheet para buscar y agregar productos a la requisición."""
    colors = _colors(view.page)

    busqueda = ft.TextField(
        hint_text="Buscar producto...",
        prefix_icon=ft.Icons.SEARCH,
        border_radius=12,
        autofocus=True,
    )

    resultados = ft.ListView(
        expand=True,
        spacing=5,
        padding=5,
    )
    view._resultados_buscador = resultados
    view._bs_buscador = None

    def on_change(e):
        view._buscar_productos_buscador(e.control.value, resultados)

    busqueda.on_change = on_change

    def close(e):
        bs.open = False
        view.page.update()

    def agregar_y_cerrar(producto):
        view._agregar_producto_req(producto)
        bs.open = False
        view.page.update()

    bs = ft.BottomSheet(
        content=ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Text("Buscar Producto", size=18, weight="bold"),
                    ft.IconButton(ft.Icons.CLOSE, on_click=close),
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                busqueda,
                ft.Container(
                    content=resultados,
                    height=400,
                ),
            ], spacing=10),
            padding=20,
        ),
        is_scroll_controlled=True,
        bgcolor=colors['surface'],
    )

    view.page.overlay.append(bs)
    view._bs_buscador = bs
    bs.open = True
    view.page.update()

    view._buscar_productos_buscador("", resultados)


def build_agregar_producto_req_dialog(view, producto, disponible):
    colors = _colors(view.page)
    es_pesable = getattr(producto, 'es_pesable', False)

    almacen_origen = getattr(view, '_origen_dropdown', None)
    origen = almacen_origen.value if almacen_origen else "principal"

    db = next(get_db_adaptive())
    disp = 0
    try:
        exist = db.query(Existencia).filter(
            Existencia.producto_id == producto.id,
            Existencia.almacen == origen,
        ).first()
        disp = exist.cantidad if exist else 0
    finally:
        db.close()
    disponible = disp

    stock_color = colors['success'] if disponible > 0 else colors['error']

    stock_info = ft.Container(
        content=ft.Row([
            ft.Icon(ft.Icons.INVENTORY_2_ROUNDED, size=16, color=stock_color),
            ft.Text(f"Disponible: {disponible} {producto.unidad_medida or 'uds'}", size=12, color=stock_color, weight="bold"),
        ], spacing=5),
        bgcolor=colors['card'],
        padding=10,
        border_radius=8,
    )

    def _calcular_desde_unidades(e):
        try:
            cant = float(cant_x_unidad_input.value or 0)
            peso_u = float((peso_x_unidad_input.value or "0").replace(',', '.').strip().rstrip('-').rstrip('+') or 0)
            peso_total_input.value = f"{cant * peso_u:.3f}"
            peso_total_input.update()
        except Exception:
            peso_total_input.value = "0.000"
            peso_total_input.update()

    def _calcular_desde_total(e):
        try:
            total = float((peso_total_input.value or "0").replace(',', '.').strip().rstrip('-').rstrip('+') or 0)
            cant = float(cant_x_unidad_input.value or 1)
            if cant > 0:
                peso_x_unidad_input.value = f"{total / cant:.3f}"
                peso_x_unidad_input.update()
        except Exception:
            pass

    is_mobile = view.page.width < 700 if view.page else False
    content_width = None
    if is_mobile and view.page and view.page.width:
        content_width = max(280, min(view.page.width - 60, 420))

    if es_pesable:
        cant_x_unidad_input = ft.TextField(
            label="Und.", value="1", keyboard_type=ft.KeyboardType.NUMBER,
            autofocus=True, border_radius=10, expand=True,
            on_change=_calcular_desde_unidades,
        )
        peso_x_unidad_input = ft.TextField(
            label="Kg/unidad", value="0.100", keyboard_type=ft.KeyboardType.NUMBER,
            border_radius=10, expand=True,
            on_change=_calcular_desde_unidades,
        )
        peso_total_input = ft.TextField(
            label="Peso Total", value="0.000", keyboard_type=ft.KeyboardType.NUMBER,
            border_radius=10, expand=True, suffix_text="kg",
            on_change=_calcular_desde_total,
        )
        if is_mobile:
            campos = ft.Column(
                [cant_x_unidad_input, peso_x_unidad_input, peso_total_input], spacing=8
            )
        else:
            campos = ft.Row(
                [cant_x_unidad_input, peso_x_unidad_input, peso_total_input], spacing=8
            )
    else:
        cant_input = ft.TextField(
            label="Cantidad", value="1", keyboard_type=ft.KeyboardType.NUMBER,
            autofocus=True, border_radius=10, expand=True,
        )
        campos = cant_input

    def on_agregar(e):
        if es_pesable:
            try:
                cant_und = int(float(cant_x_unidad_input.value.replace(",", "").replace(" ", "")))
                if cant_und <= 0:
                    raise ValueError()
            except (ValueError, AttributeError):
                cant_x_unidad_input.error_text = "Número mayor a 0"
                cant_x_unidad_input.update()
                return
            try:
                peso_total = float(peso_total_input.value.replace(',', '.'))
                if peso_total < 0:
                    raise ValueError()
            except ValueError:
                peso_total_input.error_text = "Peso válido mayor a 0"
                peso_total_input.update()
                return
            cantidad = cant_und
            peso = peso_total
        else:
            try:
                cantidad = int(float(cant_input.value.replace(",", "").replace(" ", "")))
                if cantidad <= 0:
                    raise ValueError()
            except (ValueError, AttributeError):
                cant_input.error_text = "Número entero mayor a 0"
                cant_input.update()
                return
            peso = 0.0

        existe = next((item for item in view.lista_productos_req if item['producto_id'] == producto.id), None)
        if existe:
            existe['cantidad'] += cantidad
            existe['peso'] = (existe.get('peso') or 0) + peso
        else:
            view.lista_productos_req.append({
                'producto_id': producto.id,
                'nombre': producto.nombre,
                'cantidad': cantidad,
                'peso': peso,
                'unidad': producto.unidad_medida or 'uds',
                'es_pesable': es_pesable,
            })

        dialog.open = False
        view._actualizar_lista_productos()
        view.page.update()

        if getattr(view, '_bs_buscador', None):
            view._bs_buscador.open = False

        from usr.notifications import show_success
        show_success(f"+ {producto.nombre}")

    dialog = ft.AlertDialog(
        title=ft.Text(f"Agregar: {producto.nombre}"),
        content=ft.Column([
            stock_info,
            ft.Container(height=10),
            ft.Text(f"Unidad: {producto.unidad_medida or 'uds'}", size=12, color=colors['text_secondary']),
            ft.Container(height=5),
            campos,
        ], tight=True, width=content_width),
        actions=[
            ft.TextButton("Cancelar", on_click=lambda _: setattr(dialog, 'open', False) or view.page.update()),
            ft.ElevatedButton("Agregar", on_click=on_agregar, bgcolor=colors['accent'], color="white"),
        ],
    )

    view.page.overlay.append(dialog)
    dialog.open = True
    view.page.update()
