import flet as ft
from usr.views.stock.helpers import get_safe_colors, get_mapped_color

def build_stat_card(title, value_control, icon, color):
    colors = get_safe_colors(None) # Default or pass page
    # In a real implementation, we'd pass the page or colors object
    return ft.Container(
        content=ft.Row([
            ft.Container(
                content=ft.Icon(icon, color=color, size=24),
                bgcolor=ft.Colors.with_opacity(0.2, color),
                padding=10, border_radius=12,
            ),
            ft.Column([
                ft.Text(title, size=12, color=colors['text_secondary']),
                value_control
            ], spacing=0)
        ], spacing=12),
        bgcolor=colors['card'],
        padding=12,
        border_radius=16,
        border=ft.border.all(1, colors['border']),
        width=160,
    )

def build_product_card(p, stock_actual, color, stock_por_almacen, peso_neto, colors):
    # Stock per warehouse info
    almacen_info = ft.Container(
        content=ft.Column([
            ft.Text("Stock por almacén:", size=11, weight="bold", color=colors['text_primary']),
            ft.Column([
                ft.Text(f"{k.capitalize()}: {v:.0f}", size=10) for k, v in stock_por_almacen.items()
            ], spacing=0),
        ], spacing=2),
        bgcolor=colors['blue_50'],
        padding=8,
        border_radius=6,
        margin=ft.margin.only(top=5)
    )
    
    # Weight view
    peso_view = ft.Container()
    if getattr(p, 'es_pesable', False) and peso_neto != 0:
        peso_view = ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.SCALE_ROUNDED, size=16, color=colors['accent']),
                ft.Text(f"Peso en Stock: {peso_neto:.2f} kg", size=14, weight=ft.FontWeight.W_600, color=colors['accent']),
            ], spacing=8),
            bgcolor=colors['blue_50'],
            border_radius=8,
            padding=ft.padding.symmetric(horizontal=10, vertical=8),
            margin=ft.margin.only(top=5, bottom=5)
        )
    
    return ft.Container(
        content=ft.Column([
            ft.Row([
                ft.Column([
                    ft.Text(p.nombre, weight="bold", size=16, color=colors['text_primary']),
                    ft.Text(f"Cat: {p.categoria.nombre if p.categoria else 'N/A'}", size=12, color=colors['text_secondary']),
                ], spacing=2, expand=True),
                ft.Column([
                    ft.Text(f"{stock_actual:.0f}", color=color, weight="bold", size=20),
                    ft.Text("uds", color=color, size=10, weight="bold"),
                ], horizontal_alignment="center"),
            ], alignment="spaceBetween"),
            peso_view,
            almacen_info,
            ft.Divider(height=1, color=colors['border']),
            ft.Row([
                ft.Text(f"Código: {p.codigo or '---'}", size=12, color=colors['text_secondary']),
                ft.Row([
                    ft.TextButton(
                        "Historial", 
                        icon=ft.Icons.HISTORY,
                        on_click=None # To be set by the view
                    )
                ])
            ], alignment="spaceBetween")
        ], spacing=8),
        padding=16, 
        bgcolor=colors['card'], 
        border_radius=12, 
        border=ft.border.all(1, colors['border']),
    )
