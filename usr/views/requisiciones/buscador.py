import flet as ft
from usr.theme import get_colors
from usr.database.base import get_db_adaptive
from usr.views.requisiciones.service import RequisicionService


def _c(page):
    return get_colors(page)


class ProductoBuscadorSheet:
    def __init__(self, page, on_product_select=None):
        self.page = page
        self.on_product_select = on_product_select
        self.bs = None
        self._open = False

    @property
    def is_open(self):
        return self._open

    def close(self):
        if self.bs:
            self.bs.open = False
            self.page.update()
        self._open = False

    def show(self):
        colors = _c(self.page)

        busqueda = ft.TextField(
            hint_text="Buscar producto...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=12,
            autofocus=True,
        )

        resultados_lista = ft.ListView(expand=True, spacing=5, padding=5)
        resultados_lista.controls.append(
            ft.Text("Escriba para buscar...", color=colors['text_secondary'], text_align="center")
        )

        def search(texto):
            try:
                productos = self._search_productos(texto)
            except:
                return

            old_controls = list(resultados_lista.controls)
            resultados_lista.controls.clear()
            old_controls.clear()

            for p in productos:
                row = self._build_result_row(p, colors)
                resultados_lista.controls.append(row)

            if not productos and texto:
                resultados_lista.controls.append(
                    ft.Text("Sin resultados", color=colors['text_secondary'], text_align="center")
                )

            try:
                resultados_lista.update()
            except:
                pass

        busqueda.on_change = lambda e: search(e.control.value)

        def close_handler(e):
            self.close()

        self.bs = ft.BottomSheet(
            content=ft.Container(
                content=ft.Column([
                    ft.Row([
                        ft.Text("Buscar Producto", size=18, weight="bold"),
                        ft.IconButton(ft.Icons.CLOSE, on_click=close_handler),
                    ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                    busqueda,
                    ft.Container(content=resultados_lista, height=400),
                ], spacing=10),
                padding=20,
            ),
            is_scroll_controlled=True,
            bgcolor=colors['surface'],
        )

        self.page.overlay.append(self.bs)
        self._open = True
        self.bs.open = True
        self.page.update()

    def _search_productos(self, texto):
        db = next(get_db_adaptive())
        try:
            return RequisicionService.get_productos(db, texto)
        finally:
            db.close()

    def _build_result_row(self, p, colors):
        es_pesable = getattr(p, 'es_pesable', False)
        badge = ft.Container(
            content=ft.Text("PESABLE", size=9, color="white", weight="bold"),
            bgcolor=colors['warning'],
            padding=ft.padding.symmetric(horizontal=4, vertical=1),
            border_radius=3,
        ) if es_pesable else ft.Container()

        return ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Text(p.nombre, weight="bold", size=14, color=colors['text_primary']),
                    ft.Row([
                        ft.Text(f"{p.unidad_medida or 'uds'}", size=11, color=colors['text_secondary']),
                        badge,
                    ], spacing=5),
                ], expand=True),
                ft.Container(
                    content=ft.Icon(ft.Icons.ADD_CIRCLE, color=colors['success'], size=28),
                    on_click=lambda _, prod=p: self._select_product(prod),
                    padding=5,
                ),
            ], spacing=10),
            padding=12,
            bgcolor=colors['card'],
            border_radius=10,
            ink=True,
            on_click=lambda _, prod=p: self._select_product(prod),
        )

    def _select_product(self, producto):
        self.close()
        if self.on_product_select:
            self.on_product_select(producto)
