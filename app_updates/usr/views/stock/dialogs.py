import flet as ft
from usr.theme import get_colors

def build_producto_historial_dialog(producto, movimientos):
    colors = get_colors(None) # Page will be passed or handled by controller
    
    mov_list = ft.ListView(height=400, spacing=8)
    for m in movimientos:
        is_entrada = m.tipo == "entrada"
        icon = ft.Icons.ADD_CIRCLE_OUTLINE if is_entrada else ft.Icons.REMOVE_CIRCLE_OUTLINE
        color = colors['success'] if is_entrada else colors['error']
        
        es_pesable = producto.es_pesable if producto else False
        unidad_prod = producto.unidad_medida if producto else 'unidad'
        
        if es_pesable and (m.peso_total or 0) > 0:
            cantidad_display = f"{(m.peso_total or 0):.3f} kg"
            cantidad_valor = m.peso_total or 0
        else:
            cantidad_display = f"{int(m.cantidad)} {unidad_prod}"
            cantidad_valor = m.cantidad
        
        factura_texto = ""
        if m.factura:
            factura_texto = f" - 📄 {m.factura.numero_factura}"
        
        mov_list.controls.append(
            ft.Container(
                content=ft.Row([
                    ft.Container(
                        content=ft.Icon(icon, color=color, size=24),
                        padding=ft.padding.only(right=10)
                    ),
                    ft.Column([
                        ft.Row([
                            ft.Text(f"{m.tipo.upper()}{factura_texto}", weight="bold", size=14, selectable=True),
                        ], alignment=ft.MainAxisAlignment.START, spacing=2),
                        ft.Text(
                            cantidad_display, 
                            size=12, 
                            color="#9E9E9E",
                            selectable=True
                        ),
                        ft.Text(
                            m.fecha_movimiento.strftime('%d/%m/%Y %H:%M'), 
                            size=11, 
                            color="#757575",
                            selectable=True
                        ),
                    ],
                    alignment=ft.MainAxisAlignment.START,
                    spacing=2,
                    expand=True,
                    ),
                    ft.Text(
                        f"{'+' if is_entrada else '-'}{cantidad_valor:.3f}" if es_pesable and (m.peso_total or 0) > 0 else f"{'+' if is_entrada else '-'}{int(cantidad_valor)}", 
                        color=color, 
                        weight="bold",
                        size=16
                    ),
                ], spacing=10),
                bgcolor=colors['bg'],
                padding=15,
                border_radius=10,
                margin=ft.margin.only(bottom=8),
            )
        )
    
    return ft.AlertDialog(
        title=ft.Text(f"Historial: {producto.nombre}"),
        content=ft.Column([ft.Divider(), mov_list], tight=True, width=450),
        actions=[ft.TextButton("Cerrar", on_click=lambda e: None)] # Callback handled by controller
    )


def build_existencias_dialog(producto, existencias, on_ajustar, on_close):
    colors = get_colors(None)
    es_pesable = getattr(producto, 'es_pesable', False)

    def _fmt(cant, unidad):
        if es_pesable:
            return f"{cant:.2f} {unidad}"
        return f"{cant:.0f} {unidad}"

    rows = []
    if existencias:
        for e in existencias:
            alm = e.almacen
            cant = e.cantidad or 0
            unidad = e.unidad or (producto.unidad_medida if producto else 'unidad')
            rows.append(
                ft.Container(
                    content=ft.Row([
                        ft.Column([
                            ft.Text(alm.capitalize(), weight="bold", size=15, color=colors['text_primary']),
                            ft.Text(f"Stock actual: {_fmt(cant, unidad)}", size=12, color=colors['text_secondary']),
                        ], spacing=2, expand=True),
                        ft.ElevatedButton(
                            "Ajustar", icon=ft.Icons.EDIT,
                            on_click=lambda _, a=alm, c=cant, u=unidad: on_ajustar(a, c, u),
                            style=ft.ButtonStyle(padding=ft.padding.symmetric(horizontal=12, vertical=8)),
                        )
                    ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                    bgcolor=colors['card'],
                    padding=12,
                    border_radius=10,
                    margin=ft.margin.only(bottom=8),
                    border=ft.border.all(1, colors['border']),
                )
            )
    else:
        rows.append(ft.Container(
            content=ft.Text("Este producto no tiene existencias registradas.", color=colors['text_secondary']),
            padding=10,
        ))

    unidad_prod = producto.unidad_medida if producto else 'unidad'
    stock_min = producto.stock_minimo if producto else 0

    contenido = ft.Column([
        ft.Container(
            content=ft.Text(
                f"Unidad: {unidad_prod}   •   Stock mínimo: {stock_min:.0f}",
                size=12, color=colors['text_secondary']
            ),
            padding=ft.padding.only(bottom=8),
        ),
        ft.ListView(controls=rows, height=360, spacing=0, padding=0, expand=False),
    ], tight=True, width=460)

    return ft.AlertDialog(
        title=ft.Text(f"Existencias: {producto.nombre}", size=18, weight="bold", color=colors['text_primary']),
        content=contenido,
        actions=[ft.TextButton("Cerrar", on_click=on_close)],
        actions_alignment="end",
    )


def build_ajuste_dialog(producto, almacen, cantidad_actual, unidad, on_confirm, on_cancel):
    colors = get_colors(None)
    es_pesable = getattr(producto, 'es_pesable', False)

    nueva_input = ft.TextField(
        label="Nuevo conteo físico",
        value=f"{cantidad_actual:.2f}" if es_pesable else f"{cantidad_actual:.0f}",
        keyboard_type=ft.KeyboardType.NUMBER,
        autofocus=True, border_radius=10, text_size=18,
        border_color=colors['input_border'],
        width=220,
        suffix_text=unidad,
    )
    motivo_input = ft.TextField(
        label="Motivo (opcional)",
        multiline=True, min_lines=1, max_lines=3,
        border_radius=10, border_color=colors['input_border'],
        width=440,
    )

    def _confirmar(e):
        try:
            val = float(nueva_input.value.replace(",", "").replace(" ", ""))
            if val < 0:
                raise ValueError()
        except (ValueError, AttributeError):
            nueva_input.error_text = "Número válido ≥ 0"
            nueva_input.update()
            return
        on_confirm(val, motivo_input.value or "")

    stock_actual_txt = f"{cantidad_actual:.2f} {unidad}" if es_pesable else f"{cantidad_actual:.0f} {unidad}"

    return ft.AlertDialog(
        title=ft.Text(f"Ajustar: {almacen.capitalize()}", size=18, weight="bold", color=colors['text_primary']),
        content=ft.Column([
            ft.Text(f"Stock actual: {stock_actual_txt}", size=13, color=colors['text_secondary']),
            ft.Divider(height=8, color="transparent"),
            nueva_input,
            ft.Container(height=8),
            motivo_input,
        ], tight=True, width=440),
        actions=[
            ft.TextButton("Cancelar", on_click=on_cancel),
            ft.ElevatedButton("Confirmar ajuste", on_click=_confirmar, bgcolor=colors['accent'], color="white"),
        ],
        actions_alignment="space-between",
    )
