import flet as ft


def create_compra_lista_card(item, colors, callbacks):
    def make_stock_row(almacen, cantidad):
        return ft.Container(
            content=ft.Row([
                ft.Container(
                    content=ft.Text(f"{almacen.title()}", size=12, color=colors['text_secondary']),
                    padding=ft.padding.only(right=4),
                ),
                ft.Text(f"{cantidad:.0f}", size=14, weight="bold", color=colors['text_primary']),
                ft.Container(expand=True),
                ft.IconButton(
                    ft.Icons.EDIT_OUTLINED,
                    icon_size=16,
                    icon_color=colors['accent'],
                    tooltip=f"Corregir stock en {almacen}",
                    on_click=lambda _: callbacks.get('on_corregir')(item, almacen),
                ),
            ], spacing=2, vertical_alignment="center"),
            bgcolor=colors['card_hover'],
            padding=ft.padding.symmetric(horizontal=10, vertical=6),
            border_radius=8,
        )

    return ft.Container(
        content=ft.Column([
            ft.Text(item["nombre"], weight="bold", size=15, color=colors['text_primary']),
            ft.Container(height=4),
            make_stock_row("principal", item["stock_principal"]),
            ft.Container(height=4),
            make_stock_row("restaurante", item.get("stock_restaurante", 0)),
            ft.Container(height=6),
            ft.Row([
                ft.ElevatedButton(
                    "📥 Entrada",
                    bgcolor=ft.Colors.GREEN_600,
                    color="white",
                    on_click=lambda _: callbacks.get('on_entrada')(item),
                ),
                ft.OutlinedButton(
                    "🗑️",
                    on_click=lambda _: callbacks.get('on_eliminar')(item["id"]),
                    style=ft.ButtonStyle(color=colors['error']),
                ),
            ], spacing=8),
        ], spacing=0),
        padding=12,
        bgcolor=colors['card'],
        border_radius=10,
        border=ft.border.all(1, colors['border']),
    )
