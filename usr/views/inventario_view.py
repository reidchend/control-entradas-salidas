import flet as ft
import asyncio
import threading
from datetime import datetime
from usr.database.base import get_db, get_db_adaptive, is_online
from usr.database.local_replica import LocalReplica
from usr.database.conn import get_local_conn
from usr.models import Categoria, Producto, Movimiento, Existencia, CompraListaItem
from usr.logger import get_logger
from usr.theme import get_colors
from usr.error_handler import show_error
from usr.notifications import show_success, show_error as show_error_notif
from usr.views.inventario.helpers import get_attr, get_safe_colors
from usr.views.inventario.categories import (
    create_categoria_card_from_dict,
    get_card_bg,
)
from usr.views.inventario.products import (
    create_producto_item_from_dict,
    get_almacenes,
)
from usr.views.inventario.dialogs import (
    show_cantidad_dialog,
    show_correccion_dialog,
    show_agregar_producto_dialog,
)
from usr.views.inventario.movements import registrar_movimiento
from usr.views.inventario.shopping_list import create_compra_lista_card


logger = get_logger(__name__)


class InventarioView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.padding = ft.padding.only(left=10, right=10, bottom=16, top=8)
        self.bgcolor = '#1A1A1A'

        self.search_field = None
        self.productos_list = None
        self.active_dialog = None
        self._search_timer = None
        self._connection_thread = None

        self.categorias_grid = ft.GridView(
            expand=True, runs_count=5, max_extent=120,
            child_aspect_ratio=0.8, spacing=10, run_spacing=10,
        )

        self.main_content_area = ft.Container(
            content=self.categorias_grid, expand=True,
        )

        self._vista_requisicion_activa = False
        self.panel_requisicion = None
        self.lista_requisicion = []
        self._productos_req = []

        self._vista_lista_compra_activa = False
        self.compras_lista_list = ft.ListView(expand=True, spacing=10, padding=ft.padding.only(top=10))
        self._item_compra_actual = None

        self.categoria_seleccionada = None
        self.producto_seleccionado = None
        self._is_initialized = False
        self._categorias_cache = None
        self._productos_cache = None
        self._existencias_cache = None
        self._snack = None

        self._build_ui()

    def on_theme_change(self):
        if not self.page:
            return
        colors = get_safe_colors(self.page)
        self.bgcolor = colors['bg']
        if hasattr(self, 'main_content_area'):
            self.main_content_area.bgcolor = colors['surface']
        if hasattr(self, 'search_field') and self.search_field:
            self.search_field.border_color = colors['input_border']
            self.search_field.focused_border_color = colors['accent']
        if hasattr(self, 'header_container'):
            self._build_ui()
        if hasattr(self, 'categorias_grid') and not self.categoria_seleccionada:
            if self._categorias_cache:
                if isinstance(self._categorias_cache[0], dict):
                    self.categorias_grid.controls = [
                        create_categoria_card_from_dict(c, get_safe_colors(self.page), self._on_categoria_click)
                        for c in self._categorias_cache
                    ]
                else:
                    self.categorias_grid.controls = [
                        self._create_categoria_card(c)
                        for c in self._categorias_cache
                    ]
                try:
                    self.categorias_grid.update()
                except Exception:
                    pass
            else:
                self.page.run_task(self._load_categorias)

    def did_mount(self):
        if not self._is_initialized:
            if self.page:
                self.page.run_task(self._load_categorias)
            self._is_initialized = True
        self._update_connection_indicator()
        from usr.database.sync_callbacks import register_sync_callback
        register_sync_callback(self._on_sync_complete)
        import time
        def check_connection_loop():
            while True:
                time.sleep(10)
                page = getattr(self, 'page', None)
                if page:
                    self._update_connection_indicator()
                    try:
                        page.update()
                    except Exception as e:
                        show_error("Error updating page", e, "inventario_view.check_connection_loop")
        self._connection_thread = threading.Thread(target=check_connection_loop, daemon=True)
        self._connection_thread.start()

    def will_unmount(self):
        from usr.database.sync_callbacks import unregister_sync_callback
        unregister_sync_callback(self._on_sync_complete)

    def _on_sync_complete(self):
        if hasattr(self, 'page') and self.page and self.visible:
            self.page.run_task(self._load_categorias)

    def on_sync_complete(self):
        self._on_sync_complete()

    def _build_ui(self):
        try:
            colors = get_safe_colors(self.page)

            self._connection_indicator = ft.Container(
                content=ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18),
                tooltip="Conectado", padding=5,
                on_click=self._on_sync_indicator_click
            )

            self._btn_lista_compra = ft.IconButton(
                icon=ft.Icons.SHOPPING_CART_OUTLINED,
                on_click=lambda _: self._toggle_lista_compra(),
                tooltip="Lista de Compras", icon_color=colors['text_secondary'],
            )

            self._btn_lista_compra_active = ft.IconButton(
                icon=ft.Icons.SHOPPING_CART,
                on_click=lambda _: self._toggle_lista_compra(),
                tooltip="Lista de Compras", icon_color=colors['accent'],
                visible=False,
            )

            self.header_container = ft.Container(
                content=ft.Row([
                    ft.Column([
                        ft.Text("Inventario", size=22, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                        ft.Text("Gestión de existencias", size=12, color=colors['text_secondary']),
                    ], expand=True, spacing=0),
                    ft.Container(),
                    self._connection_indicator,
                    self._btn_lista_compra,
                    self._btn_lista_compra_active,
                    ft.IconButton(
                        icon=ft.Icons.REFRESH_ROUNDED,
                        on_click=lambda _: self._on_refresh(),
                        tooltip="Recargar desde BD",
                        icon_color=colors['text_secondary'],
                    ),
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                margin=ft.margin.only(bottom=10),
            )

            self.search_field = ft.TextField(
                hint_text="Buscar...",
                prefix_icon=ft.Icons.SEARCH_ROUNDED,
                border_radius=12, border_color=colors['input_border'],
                focused_border_color=colors['accent'],
                height=45, text_size=14,
                on_change=self._on_search_change,
            )

            self.content = ft.Column([
                self.header_container,
                self.search_field,
                ft.Container(height=5),
                self.main_content_area,
            ], spacing=0, expand=True)

        except Exception as e:
            show_error("Error building UI", e, "inventario_view._build_ui")
            logger.error(f"Error UI: {e}")

    def _on_refresh(self):
        if not self.page:
            return
        from usr.database.base import is_online as base_is_online
        from usr.database import get_sync_manager
        online = base_is_online()
        if online:
            sync_mgr = get_sync_manager()
            if sync_mgr:
                sync_mgr.force_sync_now()
        self.page.run_task(self._load_categorias, True)
        if self.categoria_seleccionada:
            self._load_productos()
        for control in self.page.overlay[:]:
            if isinstance(control, ft.SnackBar):
                self.page.overlay.remove(control)
        snack = ft.SnackBar(
            content=ft.Text("🔄 Actualizando..."),
            bgcolor=ft.Colors.BLUE_600, duration=1,
        )
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()

    async def _on_sync_indicator_click(self, e=None):
        try:
            from usr.database import get_sync_manager
            sync_mgr = get_sync_manager()
            if not sync_mgr or not self.page:
                return
            self._update_connection_indicator()
            self.page.update()
        except Exception as ex:
            print(f"[ERROR] _on_sync_indicator_click: {ex}")
            import traceback; traceback.print_exc()
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al verificar conexión", ex)
            except:
                pass

    def _show_snack_bar(self, message, bgcolor):
        if not self.page:
            return
        snack = ft.SnackBar(
            content=ft.Text(message, weight=ft.FontWeight.BOLD),
            bgcolor=bgcolor, duration=5,
        )
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()

    def _update_connection_indicator(self):
        from usr.database import get_sync_manager, get_pending_movimientos_count
        from usr.database.base import is_online as base_is_online
        if not hasattr(self, '_connection_indicator'):
            return
        sync_mgr = get_sync_manager()
        pending = get_pending_movimientos_count()
        online = base_is_online()

        if online:
            self._connection_indicator.content = ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18)
            self._connection_indicator.tooltip = f"Conectado - {pending} cambios pendientes" if pending else "Conectado"
        else:
            self._connection_indicator.content = ft.Icon(ft.Icons.WIFI_OFF, color=ft.Colors.RED_400, size=18)
            self._connection_indicator.tooltip = f"Modo offline - {pending} cambios pendientes"
        try:
            self._connection_indicator.update()
        except Exception:
            pass

    async def _load_categorias(self, force_refresh=False):
        if not self.page:
            return
        try:
            local_categorias = LocalReplica.get_categorias()
            if local_categorias:
                self._categorias_cache = local_categorias
                self.categorias_grid.controls = [
                    create_categoria_card_from_dict(c, get_safe_colors(self.page), self._on_categoria_click)
                    for c in local_categorias
                ]
                self.update()
            if force_refresh or not local_categorias:
                from usr.database.base import check_connection
                if check_connection():
                    db = next(get_db_adaptive())
                    try:
                        categorias = db.query(Categoria).order_by(Categoria.nombre).all()
                        cats_data = [
                            {"id": c.id, "nombre": c.nombre, "color": c.color,
                             "descripcion": c.descripcion, "imagen": c.imagen,
                             "activo": c.activo, "created_at": str(c.created_at) if c.created_at else None,
                             "updated_at": str(c.updated_at) if c.updated_at else None}
                            for c in categorias
                        ]
                        LocalReplica.save_categorias(cats_data)
                        self._categorias_cache = cats_data
                        self.categorias_grid.controls = [
                            create_categoria_card_from_dict(c, get_safe_colors(self.page), self._on_categoria_click)
                            for c in cats_data
                        ]
                        self.update()
                        if self.page:
                            snack = ft.SnackBar(
                                content=ft.Text("✓ Datos actualizados desde servidor"),
                                bgcolor=ft.Colors.GREEN_700, duration=2,
                            )
                            self.page.overlay.append(snack)
                            snack.open = True
                            self.page.update()
                    finally:
                        if db:
                            db.close()
        except Exception as e:
            show_error("Error loading categories", e, "inventario_view._load_categorias")
            logger.error(f"Error carga categorías: {e}")
            self.categorias_grid.controls = [ft.Text(f"Error: {e}")]
            if self.page:
                self.update()

    def _on_categoria_click(self, cat_dict):
        try:
            categoria = type('Categoria', (), cat_dict)()
            self.page.run_task(self._handle_category_click, None, categoria)
        except Exception as ex:
            print(f"[ERROR] _on_categoria_click: {ex}")
            import traceback; traceback.print_exc()
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al seleccionar categoría", ex)
            except:
                pass

    async def _handle_category_click(self, container, categoria):
        try:
            if container:
                container.scale = 0.95
                container.update()
                await asyncio.sleep(0.1)
                container.scale = 1.0
                container.update()
                await asyncio.sleep(0.15)
            self._show_productos(categoria)
        except Exception as e:
            show_error("Error clicking category", e, "inventario_view._on_categoria_click")
            logger.error(f"Error en clic categoría: {e}")

    def _create_categoria_card(self, categoria):
        from usr.views.inventario.categories import create_categoria_card
        return create_categoria_card(categoria, get_safe_colors(self.page), self._show_productos)

    def _show_productos(self, categoria):
        try:
            self.categoria_seleccionada = categoria
            colors = get_safe_colors(self.page)
            if self.search_field:
                self.search_field.visible = False

            header_nav = ft.Container(
                content=ft.Row([
                    ft.IconButton(ft.Icons.ARROW_BACK_ROUNDED, on_click=lambda _: self._reset_view(),
                                  icon_color=colors['text_secondary']),
                    ft.Text(categoria.nombre, size=18, weight="bold", color=colors['text_primary']),
                ]),
                bgcolor=colors['surface'], padding=10, border_radius=10,
            )

            self.productos_list = ft.ListView(expand=True, spacing=10, padding=ft.padding.only(top=10))

            self.search_for_products = ft.TextField(
                hint_text="Buscar productos...", prefix_icon=ft.Icons.SEARCH_ROUNDED,
                border_radius=12, border_color=colors['input_border'],
                focused_border_color=colors['accent'],
                height=45, text_size=14,
                on_change=self._on_search_change, value="",
            )

            nueva_vista = ft.Column([header_nav, self.search_for_products, self.productos_list], expand=True, spacing=5)
            self.main_content_area.content = nueva_vista
            self._load_productos()
            if self.page:
                self.update()
        except Exception as ex:
            print(f"[ERROR] _show_productos: {ex}")
            import traceback; traceback.print_exc()
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al mostrar productos", ex)
            except:
                pass

    def _reset_view(self):
        self.categoria_seleccionada = None
        if self.search_field:
            self.search_field.value = ""
            self.search_field.hint_text = "Buscar..."
            self.search_field.visible = True
        if hasattr(self, 'search_for_products'):
            self.search_for_products.value = ""
        self.main_content_area.content = self.categorias_grid
        if self._categorias_cache:
            self.categorias_grid.controls = [
                create_categoria_card_from_dict(c, get_safe_colors(self.page), self._on_categoria_click)
                for c in self._categorias_cache
            ]
        if self.page:
            self.update()

    def _on_search_change(self, e=None):
        if self._search_timer:
            self._search_timer.cancel()

        def do_search():
            active_search_field = self.search_for_products if self.categoria_seleccionada else self.search_field
            search_term = active_search_field.value.lower().strip() if active_search_field and active_search_field.value else ""

            if self.categoria_seleccionada and hasattr(self, '_productos_cache') and self._productos_cache:
                if search_term:
                    filtered = [p for p in self._productos_cache if search_term in get_attr(p, "nombre", "").lower()]
                else:
                    filtered = self._productos_cache
                existencias_map = getattr(self, '_existencias_cache', {})
                colors = get_safe_colors(self.page)
                self.productos_list.controls = [
                    create_producto_item_from_dict(p, existencias_map.get(get_attr(p, "id", 0), {}), colors, {
                        'on_entrada': self._show_cantidad_dialog,
                        'on_salida': self._show_cantidad_dialog,
                    })
                    for p in filtered
                ]
            else:
                if not self._categorias_cache:
                    return
                if search_term:
                    filtered = [c for c in self._categorias_cache if search_term in get_attr(c, "nombre", "").lower()]
                else:
                    filtered = self._categorias_cache
                if not filtered:
                    colors = get_safe_colors(self.page)
                    self.categorias_grid.controls = [ft.Text("Sin resultados", size=16, color=colors['text_secondary'])]
                else:
                    self.categorias_grid.controls = [
                        create_categoria_card_from_dict(c, get_safe_colors(self.page), self._on_categoria_click)
                        for c in filtered
                    ]
            if self.page:
                self.update()

        self._search_timer = threading.Timer(0.3, do_search)
        self._search_timer.start()

    def _load_productos(self, search_term=""):
        if not self.categoria_seleccionada:
            return
        try:
            cat_id = (self.categoria_seleccionada.id if hasattr(self.categoria_seleccionada, 'id')
                      else self.categoria_seleccionada.get('id'))
            local_productos = LocalReplica.get_productos(cat_id)
            local_existencias = LocalReplica.get_existencias()

            existencias_map = {}
            for ext in local_existencias:
                prod_id = ext.get('producto_id')
                almacen = ext.get('almacen')
                if prod_id not in existencias_map:
                    existencias_map[prod_id] = {}
                existencias_map[prod_id][almacen] = ext.get('cantidad', 0)

            self._productos_cache = local_productos
            self._existencias_cache = existencias_map

            if search_term:
                local_productos = [p for p in local_productos if search_term.lower() in p.get("nombre", "").lower()]

            colors = get_safe_colors(self.page)
            items = [
                create_producto_item_from_dict(p, existencias_map.get(p.get("id"), {}), colors, {
                    'on_entrada': self._show_cantidad_dialog,
                    'on_salida': self._show_cantidad_dialog,
                })
                for p in local_productos
            ]
            self.productos_list.controls = items if items else [ft.Text("No hay productos")]
            if self.page:
                self.update()
        except Exception as e:
            show_error("Error loading products", e, "inventario_view._load_productos_por_categoria")
            logger.error(f"Error carga productos: {e}")

    def _show_cantidad_dialog(self, producto, tipo=None, on_success=None):
        if tipo is None:
            tipo = "entrada"
        show_cantidad_dialog(self, producto, tipo, on_success)

    def _close_dialog(self, e=None):
        if self.active_dialog:
            self.active_dialog.open = False
            if self.page:
                try:
                    self.page.overlay.remove(self.active_dialog)
                except ValueError:
                    pass
                self.page.update()
            self.active_dialog = None

    def _toggle_lista_compra(self):
        if not self.page:
            return
        try:
            self._vista_lista_compra_activa = not self._vista_lista_compra_activa
            if self._vista_lista_compra_activa:
                self._btn_lista_compra.visible = False
                self._btn_lista_compra_active.visible = True
                self._build_compras_lista_panel()
                self._load_compras_lista()
            else:
                self._btn_lista_compra.visible = True
                self._btn_lista_compra_active.visible = False
                self.main_content_area.content = self.categorias_grid
                if self._categorias_cache:
                    self.categorias_grid.controls = [
                        create_categoria_card_from_dict(c, get_safe_colors(self.page), self._on_categoria_click)
                        for c in self._categorias_cache
                    ]
                self.search_field.visible = True
            self.update()
        except Exception as ex:
            logger.error(f"Error toggling lista compra: {ex}")

    def _build_compras_lista_panel(self):
        colors = get_safe_colors(self.page)
        header = ft.Container(
            content=ft.Row([
                ft.IconButton(
                    ft.Icons.ARROW_BACK_ROUNDED,
                    on_click=lambda _: self._toggle_lista_compra(),
                    icon_color=colors['text_secondary'],
                ),
                ft.Column([
                    ft.Text("Lista de Compras", size=18, weight="bold", color=colors['text_primary']),
                    ft.Text("Productos pendientes por ingresar", size=11, color=colors['text_secondary']),
                ], expand=True, spacing=0),
                ft.ElevatedButton(
                    "➕ Agregar", bgcolor=colors['accent'], color="white",
                    on_click=lambda _: self._show_agregar_producto_dialog(),
                ),
            ]),
            padding=ft.padding.only(bottom=8),
        )
        self._compras_header = header
        self.search_field.visible = False
        self.main_content_area.content = ft.Column(
            [self._compras_header, self.compras_lista_list], expand=True, spacing=5,
        )

    def _load_compras_lista(self):
        try:
            conn = get_local_conn()
            cursor = conn.cursor()
            cursor.execute("SELECT id, producto_id FROM compras_lista ORDER BY id DESC")
            rows = cursor.fetchall()
            conn.close()

            items = []
            for row in rows:
                try:
                    item_id, producto_id = row
                    producto = LocalReplica.get_producto_by_id(producto_id)
                    if not producto:
                        continue
                    nombre = producto.get("nombre", "Sin nombre") if isinstance(producto, dict) else getattr(producto, "nombre", "Sin nombre")
                    existencias = LocalReplica.get_existencias(producto_id=producto_id)
                    stock_principal = next((e.get("cantidad", 0) for e in existencias if e.get("almacen") == "principal"), 0)
                    stock_restaurante = next((e.get("cantidad", 0) for e in existencias if e.get("almacen") == "restaurante"), 0)
                    items.append({
                        "id": item_id, "producto_id": producto_id, "nombre": nombre,
                        "stock_principal": stock_principal, "stock_restaurante": stock_restaurante,
                    })
                except Exception as ex:
                    logger.error(f"Error cargando item de compras_lista: {ex}")
                    continue

            self.compras_lista_items = items
            colors = get_safe_colors(self.page)
            self.compras_lista_list.controls.clear()

            if not items:
                self.compras_lista_list.controls.append(
                    ft.Container(
                        content=ft.Column([
                            ft.Icon(ft.Icons.SHOPPING_CART_OUTLINED, size=60, color=colors['text_hint']),
                            ft.Container(height=10),
                            ft.Text("Lista de compras vacía", color=colors['text_hint'], size=18, weight="bold"),
                            ft.Container(height=4),
                            ft.Text("Agrega productos con el botón \"➕ Agregar\"", color=colors['text_secondary'], size=13),
                        ], horizontal_alignment="center", spacing=0),
                        expand=True,
                        alignment=ft.alignment.center,
                    )
                )
            else:
                for item in items:
                    self.compras_lista_list.controls.append(
                        create_compra_lista_card(item, colors, {
                            'on_corregir': self._show_correccion_dialog,
                            'on_entrada': self._show_entrada_desde_lista,
                            'on_eliminar': self._eliminar_de_lista_compra,
                        })
                    )
        except Exception as ex:
            logger.error(f"Error cargando lista de compras: {ex}")
            colors = get_safe_colors(self.page)
            self.compras_lista_list.controls.clear()
            self.compras_lista_list.controls.append(
                ft.Text(f"Error al cargar: {ex}", color=colors['error'])
            )
        if self.page:
            self.page.update()

    def _show_correccion_dialog(self, item, almacen):
        show_correccion_dialog(self, item, almacen, on_success=self._refresh_compras_lista)

    def _refresh_compras_lista(self):
        self._build_compras_lista_panel()
        self._load_compras_lista()

    def _show_entrada_desde_lista(self, item):
        try:
            prod_data = LocalReplica.get_producto_by_id(item["producto_id"])
            if not prod_data:
                show_error_notif("Producto no encontrado")
                return
            producto = type("Producto", (), prod_data)() if isinstance(prod_data, dict) else prod_data
            self._item_compra_actual = item
            self._show_cantidad_dialog(producto, "entrada", on_success=lambda: self._on_entrada_compra_completada(item))
        except Exception as ex:
            show_error_notif(f"Error al preparar entrada: {ex}")
            logger.error(f"Error en entrada desde lista: {ex}")

    def _on_entrada_compra_completada(self, item):
        self._eliminar_de_lista_compra(item["id"])
        self._item_compra_actual = None

    def _eliminar_de_lista_compra(self, item_id):
        try:
            conn = get_local_conn()
            cursor = conn.cursor()
            cursor.execute("DELETE FROM compras_lista WHERE id = ?", (item_id,))
            conn.commit()
            conn.close()
            show_success("Producto eliminado de la lista")
            self._load_compras_lista()
        except Exception as ex:
            logger.error(f"Error eliminando de compras_lista: {ex}")
            show_error_notif(f"Error al eliminar: {ex}")

    def _show_agregar_producto_dialog(self):
        show_agregar_producto_dialog(self)

    def _eliminar_item_req(self, idx, tabla):
        if idx < len(self.lista_requisicion):
            self.lista_requisicion.pop(idx)
            tabla.controls.clear()
            if not self.lista_requisicion:
                tabla.controls.append(
                    ft.Container(
                        content=ft.Text("Sin productos agregados", color=ft.Colors.GREY_400, text_align="center"),
                        padding=20,
                    )
                )
            else:
                for i, item in enumerate(self.lista_requisicion):
                    tabla.controls.append(
                        ft.Container(
                            content=ft.Row([
                                ft.Text(f"{i+1}.", size=12, color=ft.Colors.GREY_500, width=30),
                                ft.Text(item["nombre"], size=13, weight="bold", expand=True),
                                ft.Text(f"{item['cantidad']:.2f} {item['unidad']}", size=12, color=ft.Colors.BLUE_700),
                                ft.IconButton(
                                    ft.Icons.DELETE_OUTLINE, icon_color=ft.Colors.RED_400, icon_size=18,
                                    on_click=lambda _, index=i: self._eliminar_item_req(index, tabla),
                                ),
                            ], spacing=10),
                            padding=10, bgcolor=ft.Colors.GREY_50, border_radius=8,
                        )
                    )
            tabla.update()

    def _registrar_movimiento(self, tipo, cantidad, peso_total=0.0, almacen=None):
        if not self.producto_seleccionado:
            return
        registrar_movimiento(self.page, self.producto_seleccionado, tipo, cantidad, peso_total, almacen)
        if self._vista_lista_compra_activa:
            self._load_compras_lista()
        elif self.categoria_seleccionada:
            self._load_productos()
