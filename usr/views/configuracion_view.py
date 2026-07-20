import asyncio
import time
import flet as ft
from sqlalchemy.orm import joinedload
from usr.models import Categoria, Producto
from usr.database.base import get_db_adaptive, is_online
from usr.notifications import show_error
from usr.views.configuracion.helpers import _colors
from usr.views.configuracion.categorias import show_categoria_dialog, create_categoria_grid, create_categoria_item_mobile
from usr.views.configuracion.productos import show_producto_dialog, create_producto_item
from usr.views.configuracion.proveedores import build_proveedores_tab, load_proveedores
from usr.views.configuracion.sistema import build_sistema_tab


def _get_tipo_label(tipo):
    labels = {
        "PRODUCTO PARA USO INTERNO": "Uso Interno",
        "PRODUCTOS PARA LA VENTA": "Venta",
        "INSUMOS": "Insumo",
    }
    return labels.get(tipo)


class ConfiguracionView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.padding = 0
        self.bgcolor = "#1A1A1A"

        self.selected_image_path = None
        self.active_dialog = None
        self.active_snackbar = None
        self.is_mobile = False

        self.lista_categorias = ft.ListView(expand=True, spacing=12, auto_scroll=False)
        self.lista_productos = ft.ListView(expand=True, spacing=12, auto_scroll=False)
        self.test_result_text = ft.Text("", size=14, weight=ft.FontWeight.BOLD)

        is_online_flag = is_online()

        self.offline_status_indicator = ft.Text(
            "ONLINE" if is_online_flag else "OFFLINE",
            size=14,
            color=ft.Colors.GREEN_400 if is_online_flag else ft.Colors.RED_400,
            weight=ft.FontWeight.BOLD,
        )

    def did_mount(self):
        if self.page:
            self.is_mobile = self.page.width < 768
            self.page.on_resize = self._on_resize
        self._build_ui()
        if self.page:
            self._load_data()

    def on_theme_change(self):
        if not self.page:
            return
        colors = _colors(self.page)
        self.bgcolor = colors['bg']
        self.update()

    def _on_resize(self, e):
        self.is_mobile = self.page.width < 768
        self.update()

    def _build_ui(self):
        colors = _colors(self.page)
        header = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(
                        content=ft.Icon(ft.Icons.SETTINGS, size=32, color=colors['white']),
                        bgcolor=colors['accent'],
                        padding=12,
                        border_radius=12
                    ),
                    ft.Column([
                        ft.Text("Configuracion", size=26, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                        ft.Text("Gestione categorias y catalogo de productos", size=13, color=colors['text_secondary']),
                    ], spacing=2, expand=True),
                ], alignment=ft.MainAxisAlignment.START),
            ], spacing=8),
            padding=ft.padding.only(left=20, right=20, top=20, bottom=15),
            bgcolor=colors['surface'],
            border_radius=ft.border_radius.only(bottom_left=20, bottom_right=20),
        )

        self.tabs = ft.Tabs(
            selected_index=0,
            animation_duration=300,
            scrollable=True,
            tabs=[
                ft.Tab(
                    text="Categorias",
                    icon=ft.Icons.CATEGORY,
                    content=self._build_categorias_tab(),
                ),
                ft.Tab(
                    text="Productos",
                    icon=ft.Icons.INVENTORY_2,
                    content=self._build_productos_tab(),
                ),
                ft.Tab(
                    text="Proveedores",
                    icon=ft.Icons.LOCAL_SHIPPING,
                    content=build_proveedores_tab(self),
                ),
                ft.Tab(
                    text="Sistema",
                    icon=ft.Icons.DASHBOARD_CUSTOMIZE,
                    content=build_sistema_tab(self),
                ),
            ],
            expand=True,
        )

        self.content = ft.Column([header, self.tabs], expand=True, spacing=0)

    def _build_categorias_tab(self):
        colors = _colors(self.page)
        fab_content = ft.Row([
            ft.Icon(ft.Icons.ADD, size=20),
            ft.Text("Nueva Categoria" if not self.is_mobile else "Nueva", weight=ft.FontWeight.BOLD),
        ], alignment=ft.MainAxisAlignment.CENTER, spacing=8)

        self.categoria_search = ft.TextField(
            hint_text="Buscar categorias...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=10,
            bgcolor=colors['card'],
            border_color=colors['border'],
            height=40,
            expand=True,
            on_change=self._filter_categorias,
        )

        return ft.Container(
            content=ft.Column([
                ft.Container(height=15),
                ft.Row([
                    self.categoria_search,
                    ft.Container(
                        content=fab_content,
                        bgcolor=colors['accent'],
                        padding=ft.padding.symmetric(horizontal=20, vertical=12),
                        border_radius=30,
                        on_click=lambda _: show_categoria_dialog(self),
                    ),
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN, spacing=10),
                ft.Container(height=15),
                self.lista_categorias,
            ], expand=True, spacing=0),
            padding=20,
            expand=True,
        )

    def _build_productos_tab(self):
        colors = _colors(self.page)
        fab_content = ft.Row([
            ft.Icon(ft.Icons.ADD_BOX, size=20),
            ft.Text("Nuevo Producto" if not self.is_mobile else "Nuevo", weight=ft.FontWeight.BOLD),
        ], alignment=ft.MainAxisAlignment.CENTER, spacing=8)

        self.producto_search = ft.TextField(
            hint_text="Buscar productos...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=10,
            bgcolor=colors['card'],
            border_color=colors['border'],
            height=40,
            expand=True,
            on_change=self._filter_productos,
        )

        return ft.Container(
            content=ft.Column([
                ft.Container(height=15),
                ft.Row([
                    self.producto_search,
                    ft.Container(
                        content=fab_content,
                        bgcolor=colors['success'],
                        padding=ft.padding.symmetric(horizontal=20, vertical=12),
                        border_radius=30,
                        on_click=lambda _: show_producto_dialog(self),
                    ),
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN, spacing=10),
                ft.Container(height=15),
                self.lista_productos,
            ], expand=True, spacing=0),
            padding=20,
            expand=True,
        )

    def _load_data(self):
        colors = _colors(self.page)
        self.is_mobile = self.page.width < 768 if self.page else False

        try:
            db = next(get_db_adaptive())
            cats = db.query(Categoria).filter(Categoria.activo == True).all()
            prods = db.query(Producto).filter(Producto.activo == True).options(
                joinedload(Producto.categoria)
            ).all()

            self.categorias_cache = cats
            self.productos_cache = prods

            if self.is_mobile:
                self.lista_categorias.controls = [create_categoria_item_mobile(self, c) for c in cats]
            else:
                self.lista_categorias.controls = create_categoria_grid(self, cats)

            self.lista_productos.controls = [create_producto_item(self, p) for p in prods]

            load_proveedores(self)

            self.update()
            db.close()
        except Exception as e:
            show_error(f"Error al cargar datos: {str(e)}")
            if db:
                db.close()

    def _filter_categorias(self, e=None):
        if not hasattr(self, 'categorias_cache'):
            return
        self._last_cat_search = time.time()
        self.page.run_task(self._debounced_filter_categorias)

    async def _debounced_filter_categorias(self):
        await asyncio.sleep(0.3)
        if time.time() - self._last_cat_search < 0.3:
            return
        search = self.categoria_search.value.lower() if self.categoria_search.value else ""
        filtered = [c for c in self.categorias_cache if search in c.nombre.lower()]
        if self.is_mobile:
            self.lista_categorias.controls = [create_categoria_item_mobile(self, c) for c in filtered]
        else:
            self.lista_categorias.controls = create_categoria_grid(self, filtered)
        self.update()

    def _filter_productos(self, e=None):
        if not hasattr(self, 'productos_cache'):
            return
        self._last_prod_search = time.time()
        self.page.run_task(self._debounced_filter_productos)

    async def _debounced_filter_productos(self):
        await asyncio.sleep(0.3)
        if time.time() - self._last_prod_search < 0.3:
            return
        search = self.producto_search.value.lower() if self.producto_search.value else ""
        filtered = [p for p in self.productos_cache if search in p.nombre.lower()]
        self.lista_productos.controls = [create_producto_item(self, p) for p in filtered]
        self.update()

    def refresh(self):
        self.is_mobile = self.page.width < 768 if self.page else False
        self._load_data()
