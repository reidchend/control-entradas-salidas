import flet as ft
from usr.views.stock.helpers import get_safe_colors, get_mapped_color

def build_stat_card(title, value_control, icon, color, on_click=None, active=False):
    colors = get_safe_colors(None) # Default or pass page
    # In a real implementation, we'd pass the page or colors object
    return ft.Container(
        content=ft.Row([
            ft.Container(
                content=ft.Icon(icon, color=color, size=20),
                bgcolor=ft.Colors.with_opacity(0.2, color),
                padding=8, border_radius=12,
            ),
            ft.Column([
                ft.Text(title, size=11, color=colors['text_secondary']),
                value_control
            ], spacing=0)
        ], spacing=10),
        bgcolor=colors['card'],
        padding=8,
        border_radius=16,
        border=ft.border.all(2 if active else 1, color if active else colors['border']),
        width=140,
        on_click=on_click,
        ink=True,
    )

def build_product_card(p, stock_actual, color, stock_por_almacen, peso_neto, colors, on_action=None):
    # Determinar la unidad de medida (uds, kg, etc)
    unidad = p.unidad_medida if (hasattr(p, 'unidad_medida') and p.unidad_medida) else "uds"
    
    # Sección de Almacenes - Más legible
    almacen_info = []
    if stock_por_almacen:
        for k, v in stock_por_almacen.items():
            almacen_info.append(ft.Text(f"{k.capitalize()}: {v:.0f}", size=11, color=colors['text_secondary']))
    
    almacen_row = ft.Row(almacen_info, wrap=True, spacing=10) if almacen_info else None

    # Formato de stock: decimales si es pesable, entero si no
    stock_display = f"{stock_actual:.2f}" if getattr(p, 'es_pesable', False) else f"{stock_actual:.0f}"

    return ft.Container(
        content=ft.Column([
            # Fila Superior: Nombre y Menú
            ft.Row([
                ft.Text(p.nombre, weight="bold", size=16, color=colors['text_primary'], expand=True, max_lines=2, overflow=ft.TextOverflow.CLIP),
                ft.PopupMenuButton(
                    items=[
                        ft.PopupMenuItem(text="Ver historial", icon=ft.Icons.HISTORY, 
                                        on_click=lambda _: on_action("historial", p) if on_action else None),
                        ft.PopupMenuItem(text="Existencias", icon=ft.Icons.INVENTORY_2_OUTLINED, 
                                        on_click=lambda _: on_action("existencias", p) if on_action else None),
                    ],
                    icon=ft.Icons.MORE_VERT,
                    icon_color=colors['text_secondary'],
                ),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            
            # Fila de Detalles: Categoría y Código
            ft.Row([
                ft.Text(f"📦 {p.categoria.nombre if p.categoria else 'S/C'}  •  🆔 {p.codigo or '---'}", 
                        size=11, color=colors['text_secondary']),
            ]),
            
            # Información de Almacenes (si existe)
            almacen_row if almacen_row else ft.Container(height=0),
            
            # Fila Inferior: Stock Destacado
            ft.Row([
                ft.Container(
                    content=ft.Row([
                        ft.Text(stock_display, color=color, weight="bold", size=18),
                        ft.Text(f" {unidad}", color=color, size=11, weight="bold"),
                    ], spacing=2),
                    padding=ft.padding.symmetric(horizontal=8, vertical=2),
                    border_radius=6,
                    bgcolor=ft.Colors.with_opacity(0.1, color),
                ),
            ], alignment=ft.MainAxisAlignment.END),
        ], spacing=6, tight=True),
        padding=15,
        bgcolor=colors['card'],
        border_radius=12,
        border=ft.border.all(1, colors['border']),
    )
