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
