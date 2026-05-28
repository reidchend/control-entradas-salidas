import flet as ft
from usr.models import Existencia
from usr.database.base import get_db_adaptive
from usr.database.local_replica import LocalReplica
from usr.notifications import show_success, show_error as show_error_notif
from usr.error_handler import show_error
from usr.views.inventario.helpers import get_attr, get_safe_colors


def show_cantidad_dialog(view, producto, tipo, on_success=None):
    view.producto_seleccionado = producto
    es_pesable = get_attr(producto, 'es_pesable', False)
    almacen_default = get_attr(producto, 'almacen_predeterminado', 'principal')

    try:
        db = next(get_db_adaptive())
        try:
            producto_id = get_attr(producto, 'id')
            existencias = db.query(Existencia).filter(Existencia.producto_id == producto_id).all()
            stock_por_almacen = {e.almacen: e.cantidad for e in existencias}
            todos_almacenes = db.query(Existencia.almacen).distinct().all()
            almacenes_disponibles = [a[0] for a in todos_almacenes]
            if "principal" not in almacenes_disponibles:
                almacenes_disponibles.append("principal")
        finally:
            db.close()
    except Exception as ex:
        show_error_notif(f"Error cargando datos: {ex}")
        return

    colors = get_safe_colors(view.page)

    def _calcular_desde_unidades(e):
        try:
            cant = float(cant_x_unidad_input.value or 0)
            peso_u_str = peso_x_unidad_input.value.replace(',', '.').strip().rstrip('-').rstrip('+')
            peso_u = float(peso_u_str or 0)
            peso_total_input.value = f"{cant * peso_u:.3f}"
            peso_total_input.update()
        except Exception as e:
            show_error("Error calculando total", e)
            peso_total_input.value = "0.000"
            peso_total_input.update()

    def _calcular_desde_total(e):
        try:
            total_str = peso_total_input.value.replace(',', '.').strip().rstrip('-').rstrip('+')
            total = float(total_str or 0)
            cant = float(cant_x_unidad_input.value or 1)
            if cant > 0:
                peso_x_unidad_input.value = f"{total / cant:.3f}"
                peso_x_unidad_input.update()
        except Exception as e:
            show_error("Error calculando desde total", e)

    cant_x_unidad_input = ft.TextField(
        label="Und.", value="1", keyboard_type=ft.KeyboardType.NUMBER,
        autofocus=True, border_radius=10, text_size=14,
        border_color=colors['input_border'], width=100,
        on_change=_calcular_desde_unidades if es_pesable else None,
    )

    peso_x_unidad_input = ft.TextField(
        label="Kg/unidad", value="0.100", keyboard_type=ft.KeyboardType.NUMBER,
        border_radius=10, text_size=14,
        border_color=colors['input_border'], width=100,
        on_change=_calcular_desde_unidades if es_pesable else None,
    )

    peso_total_input = ft.TextField(
        label="Peso Total", value="0.000", keyboard_type=ft.KeyboardType.NUMBER,
        border_radius=10, text_size=14,
        border_color=colors['input_border'], width=120,
        suffix_text="kg", focused_border_color=colors['accent'],
        on_change=_calcular_desde_total if es_pesable else None,
    )

    cant_input_normal = ft.TextField(
        label="Cantidad", value="1", keyboard_type=ft.KeyboardType.NUMBER,
        autofocus=True, border_radius=10, text_size=16,
        border_color=colors['input_border'],
    )

    almacen_options = [ft.dropdown.Option(a, a.capitalize()) for a in almacenes_disponibles]
    almacen_dropdown = ft.Dropdown(
        label="Almacén", value=almacen_default,
        options=almacen_options, border_radius=10,
    )

    stock_info = ft.Container(
        content=ft.Column([
            ft.Text("📦 Stock por almacén:", size=12, weight="bold", color=colors['accent']),
            ft.Text(" • ".join([f"{k.title()}: {v:.0f}" for k, v in stock_por_almacen.items()]) if stock_por_almacen else "Sin stock",
                   size=11, color=colors['text_secondary']),
        ], tight=True, spacing=2),
        bgcolor=colors['card_hover'], padding=12, border_radius=10,
    )

    def _al_confirmar(e):
        if es_pesable:
            try:
                cant_und = int(float(cant_x_unidad_input.value.replace(",", "").replace(" ", "")))
                if cant_und <= 0: raise ValueError()
            except (ValueError, AttributeError):
                cant_x_unidad_input.error_text = "Número mayor a 0"
                cant_x_unidad_input.update()
                return
            try:
                peso_total = float(peso_total_input.value.replace(',', '.'))
                if peso_total < 0: raise ValueError()
            except ValueError:
                peso_total_input.error_text = "Peso válido mayor a 0"
                peso_total_input.update()
                return
            cantidad_a_guardar = 0
        else:
            try:
                cantidad_a_guardar = int(float(cant_input_normal.value.replace(",", "").replace(" ", "")))
                if cantidad_a_guardar <= 0: raise ValueError()
            except (ValueError, AttributeError):
                cant_input_normal.error_text = "Número entero mayor a 0"
                cant_input_normal.update()
                return
            peso_total = 0.0

        almacen = almacen_dropdown.value or "principal"
        view._close_dialog()
        if es_pesable:
            from usr.views.inventario.movements import registrar_movimiento
            registrar_movimiento(view.page, producto, tipo, cant_und, peso_total=peso_total, almacen=almacen)
        else:
            from usr.views.inventario.movements import registrar_movimiento
            registrar_movimiento(view.page, producto, tipo, cantidad_a_guardar, almacen=almacen)
        if on_success:
            on_success()

    tipo_color = colors['success'] if tipo == "entrada" else colors['error']
    tipo_icon = "📥" if tipo == "entrada" else "📤"

    if es_pesable:
        dialog_content = ft.Column([
            ft.Container(
                content=ft.Text(get_attr(producto, 'nombre', 'Producto'), weight="bold", size=15, color=colors['text_primary']),
                padding=5, bgcolor=colors['card_hover'], border_radius=8, width=float('inf'),
            ),
            ft.Container(height=8), stock_info, ft.Container(height=8),
            ft.ResponsiveRow([
                ft.Column([almacen_dropdown], col={"xs": 12, "sm": 6}),
                ft.Column([cant_x_unidad_input], col={"xs": 12, "sm": 6}),
            ], spacing=10),
            ft.Container(height=5),
            ft.ResponsiveRow([
                ft.Column([peso_x_unidad_input], col={"xs": 12, "sm": 6}),
                ft.Column([peso_total_input], col={"xs": 12, "sm": 6}),
            ], spacing=10),
        ], tight=True, spacing=5)
    else:
        dialog_content = ft.Column([
            ft.Container(
                content=ft.Text(get_attr(producto, 'nombre', 'Producto'), weight="bold", size=15, color=colors['text_primary']),
                padding=5, bgcolor=colors['card_hover'], border_radius=8, width=float('inf'),
            ),
            ft.Container(height=8), stock_info, ft.Container(height=8),
            ft.ResponsiveRow([
                ft.Column([almacen_dropdown], col={"xs": 12, "sm": 6}),
                ft.Column([cant_input_normal], col={"xs": 12, "sm": 6}),
            ], spacing=10),
        ], tight=True, spacing=5)

    dialog_width = max(400, int(view.page.width * 0.4)) if view.page else 400

    scrollable_content = ft.ListView([dialog_content], auto_scroll=True)

    dialog = ft.AlertDialog(
        title=ft.Text(f"{tipo_icon} {tipo.capitalize()}", weight="bold", size=18, color=colors['text_primary']),
        content=ft.Container(content=scrollable_content, width=dialog_width),
        actions=[
            ft.TextButton("Cancelar", on_click=view._close_dialog, style=ft.ButtonStyle(color=colors['text_secondary'])),
            ft.ElevatedButton("Confirmar", on_click=_al_confirmar, bgcolor=tipo_color, color="white"),
        ],
        actions_alignment="space-between",
    )

    view.page.overlay.clear()
    view.page.overlay.append(dialog)
    view.active_dialog = dialog
    dialog.open = True
    view.page.update()


def show_correccion_dialog(view, item, almacen, on_success=None):
    colors = get_safe_colors(view.page)
    producto_id = item["producto_id"]
    nombre = item["nombre"]
    unidad = "unidad"
    try:
        existencia = LocalReplica.get_existencias_by_producto_almacen(producto_id, almacen)
        stock_actual = existencia.get("cantidad", 0) if existencia else 0
        unidad = existencia.get("unidad", "unidad") if existencia else "unidad"
    except Exception as ex:
        show_error_notif(f"Error cargando datos de corrección: {ex}")
        return

    es_kg = unidad == 'kg'

    cantidad_input = ft.TextField(
        label=f"Cantidad física real ({unidad})",
        value=f"{stock_actual:.2f}" if es_kg else str(int(stock_actual)),
        keyboard_type=ft.KeyboardType.NUMBER,
        autofocus=True, border_radius=10, text_size=16,
        border_color=colors['input_border'],
    )

    def _al_confirmar(e):
        try:
            valor_limpio = cantidad_input.value.replace(",", ".").replace(" ", "")
            cantidad_fisica = float(valor_limpio) if es_kg else int(float(valor_limpio))
            if cantidad_fisica < 0:
                raise ValueError()
        except (ValueError, AttributeError):
            cantidad_input.error_text = "Número válido mayor o igual a 0"
            cantidad_input.update()
            return

        view._close_dialog()

        diferencia = cantidad_fisica - stock_actual
        if diferencia == 0:
            show_success("Sin diferencia, no se crea movimiento.")
            return

        fmt_val = ".2f" if es_kg else ".0f"
        fmt_diff = ".2f" if es_kg else ".0f"

        if diferencia > 0:
            tipo = "ajuste"
            cantidad = diferencia
            msg = (f"Stock físico ({format(cantidad_fisica, fmt_val)}) > "
                   f"Sistema ({format(stock_actual, fmt_val)}) {unidad}\n"
                   f"¿Crear ajuste de +{format(diferencia, fmt_diff)} {unidad}?")
        else:
            tipo = "salida"
            cantidad = abs(diferencia)
            msg = (f"Stock físico ({format(cantidad_fisica, fmt_val)}) < "
                   f"Sistema ({format(stock_actual, fmt_val)}) {unidad}\n"
                   f"¿Crear salida de {format(cantidad, fmt_diff)} {unidad}?")

        def _confirmar_correccion(e2):
            try:
                view._close_dialog()
                from usr.views.inventario.movements import registrar_movimiento
                prod_obj = LocalReplica.get_producto_by_id(producto_id)
                producto = type("Producto", (), prod_obj)() if isinstance(prod_obj, dict) else prod_obj
                if es_kg:
                    registrar_movimiento(view.page, producto, tipo, cantidad, peso_total=cantidad, almacen=almacen)
                else:
                    registrar_movimiento(view.page, producto, tipo, cantidad, almacen=almacen)
                if on_success:
                    on_success()
            except Exception as ex:
                show_error_notif(f"Error al registrar corrección: {ex}")

        confirm = ft.AlertDialog(
            title=ft.Text("Confirmar corrección", weight="bold", color=colors['text_primary']),
            content=ft.Text(msg, color=colors['text_secondary']),
            actions=[
                ft.TextButton("Cancelar", on_click=view._close_dialog, style=ft.ButtonStyle(color=colors['text_secondary'])),
                ft.ElevatedButton("Confirmar", on_click=_confirmar_correccion, bgcolor=colors['accent'], color="white"),
            ],
            actions_alignment="space-between",
        )
        view.page.overlay.append(confirm)
        view.active_dialog = confirm
        confirm.open = True
        view.page.update()

    dialog = ft.AlertDialog(
        title=ft.Text(f"Corregir stock en {almacen.title()}", weight="bold", size=18, color=colors['text_primary']),
        content=ft.Column([
            ft.Text(nombre, weight="bold", size=14, color=colors['text_primary']),
            ft.Container(height=8),
            ft.Container(
                content=ft.Column([
                    ft.Text(f"Stock actual (sistema): {format(stock_actual, '.2f' if es_kg else '.0f')} {unidad}", size=13, color=colors['text_secondary']),
                    ft.Text("Ingresa la cantidad real en físico:", size=12, color=colors['text_secondary']),
                ]),
                bgcolor=colors['card_hover'], padding=12, border_radius=8,
            ),
            ft.Container(height=8), cantidad_input,
        ], tight=True, spacing=5),
        actions=[
            ft.TextButton("Cancelar", on_click=view._close_dialog, style=ft.ButtonStyle(color=colors['text_secondary'])),
            ft.ElevatedButton("Aplicar corrección", on_click=_al_confirmar, bgcolor=colors['accent'], color="white"),
        ],
        actions_alignment="space-between",
    )

    view.page.overlay.clear()
    view.page.overlay.append(dialog)
    view.active_dialog = dialog
    dialog.open = True
    view.page.update()


def show_agregar_producto_dialog(view):
    try:
        from usr.database.local_replica import LocalReplica
        from usr.database.conn import get_local_conn
        colors = get_safe_colors(view.page)
        productos_cache = LocalReplica.get_productos()
    except Exception as ex:
        show_error_notif(f"Error cargando productos: {ex}")
        return

    search_input = ft.TextField(
        label="Buscar producto...",
        prefix_icon=ft.Icons.SEARCH_ROUNDED,
        border_radius=10, border_color=colors['input_border'],
        autofocus=True,
        on_change=lambda e: (_filtrar(e.control.value), results_list.update() if view.page else None),
    )

    results_list = ft.ListView(expand=True, spacing=4, height=300)

    def _filtrar(texto):
        results_list.controls.clear()
        if not texto:
            results_list.controls.append(
                ft.Text("Escribe para buscar productos...", color=colors['text_secondary'], size=13)
            )
        else:
            t = texto.lower().strip()
            for p in productos_cache:
                nombre = p.get("nombre", "") if isinstance(p, dict) else getattr(p, "nombre", "")
                if t in nombre.lower():
                    pid = p.get("id") if isinstance(p, dict) else p.id
                    item = ft.Container(
                        content=ft.Text(nombre, size=14, color=colors['text_primary']),
                        padding=12, bgcolor=colors['card_hover'],
                        border_radius=8,
                        on_click=lambda _, pid=pid, nombre=nombre: _seleccionar(pid, nombre),
                    )
                    results_list.controls.append(item)
            if not results_list.controls:
                results_list.controls.append(
                    ft.Text("Sin resultados", color=colors['text_secondary'], size=13)
                )

    def _seleccionar(pid, nombre):
        try:
            conn = get_local_conn()
            cursor = conn.cursor()
            cursor.execute("SELECT id FROM compras_lista WHERE producto_id = ?", (pid,))
            if cursor.fetchone():
                conn.close()
                show_success(f"{nombre} ya está en la lista")
                view._close_dialog()
                return
            cursor.execute("INSERT INTO compras_lista (producto_id) VALUES (?)", (pid,))
            conn.commit()
            conn.close()
            view._close_dialog()
            show_success(f"{nombre} agregado a la lista de compras")
            view._load_compras_lista()
        except Exception as ex:
            show_error_notif(f"Error al agregar producto: {ex}")

    results_list.controls.append(
        ft.Text("Escribe para buscar productos...", color=colors['text_secondary'], size=13)
    )

    dialog = ft.AlertDialog(
        title=ft.Text("Agregar producto", weight="bold", size=18, color=colors['text_primary']),
        content=ft.Column([
            search_input,
            ft.Container(height=8),
            results_list,
        ], tight=True, width=350, height=400),
        actions=[ft.TextButton("Cerrar", on_click=view._close_dialog, style=ft.ButtonStyle(color=colors['text_secondary']))],
        actions_alignment="end",
    )

    view.page.overlay.clear()
    view.page.overlay.append(dialog)
    view.active_dialog = dialog
    dialog.open = True
    view.page.update()
