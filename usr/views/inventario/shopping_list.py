import flet as ft


def create_categoria_header(nombre: str, color: str, colors: dict):
    return ft.Container(
        content=ft.Row([
            ft.Container(
                width=4, height=24,
                bgcolor=color or colors.get('accent', '#6200EE'),
                border_radius=2,
            ),
            ft.Container(width=8),
            ft.Text(nombre.upper(), size=13, weight="bold", color=colors.get('text_secondary', '#666')),
            ft.Container(expand=True),
            ft.Container(
                height=1, expand=True,
                bgcolor=colors.get('border', '#E0E0E0'),
            ),
        ], spacing=0, vertical_alignment="center"),
        padding=ft.padding.only(top=16, bottom=4, left=4),
    )


def create_compra_lista_card(item, colors, callbacks):
    def fmt(cantidad, unidad):
        if unidad == 'kg':
            return f"{cantidad:.2f} kg"
        return f"{cantidad:.0f}"

    def tap_half(label, cantidad, unidad, almacen):
        texto = fmt(cantidad, unidad)
        return ft.GestureDetector(
            content=ft.Container(
                content=ft.Row([
                    ft.Text(label, size=11, color=colors['text_secondary']),
                    ft.Text(texto, size=13, weight="bold", color=colors['text_primary']),
                ], spacing=4),
                padding=ft.padding.symmetric(horizontal=8, vertical=10),
            ),
            expand=True,
            on_tap=lambda e: callbacks.get('on_corregir')(item, almacen),
        )

    return ft.Container(
        content=ft.Column([
            ft.Row([
                ft.Text(item["nombre"], weight="bold", size=14, color=colors['text_primary'], expand=True),
                ft.IconButton(
                    ft.Icons.ARROW_DOWNWARD, icon_size=18, icon_color=ft.Colors.GREEN_600,
                    tooltip="Entrada",
                    on_click=lambda _: callbacks.get('on_entrada')(item),
                ),
                ft.IconButton(
                    ft.Icons.DELETE_OUTLINE, icon_size=18, icon_color=colors['error'],
                    tooltip="Eliminar",
                    on_click=lambda _: callbacks.get('on_eliminar')(item["id"]),
                ),
            ], spacing=2, vertical_alignment="center"),
            ft.Container(height=2),
            ft.Container(
                content=ft.Row([
                    tap_half("P:", item["stock_principal"], item.get("stock_principal_unidad", "unidad"), "principal"),
                    ft.Container(width=1, height=30, bgcolor=colors.get('border', '#E0E0E0')),
                    tap_half("R:", item.get("stock_restaurante", 0), item.get("stock_restaurante_unidad", "unidad"), "restaurante"),
                ], spacing=0),
                bgcolor=colors['card_hover'],
                border_radius=6,
            ),
        ], spacing=0),
        padding=10,
        bgcolor=colors['card'],
        border_radius=8,
        border=ft.border.all(1, colors['border']),
    )
