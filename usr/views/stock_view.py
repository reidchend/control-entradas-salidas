import flet as ft
import asyncio
from sqlalchemy import func
from usr.database.base import get_db_adaptive
from usr.models import Producto, Movimiento
from usr.theme import get_colors
from usr.notifications import show_success, show_info, show_error
from usr.logger import get_logger
from usr.views.stock.helpers import get_safe_colors
from usr.views.stock.data import (
    load_categories, load_warehouses, load_products, 
    get_existencias_map, filter_products_db, get_producto_historial
)
from usr.views.stock.components import build_stat_card, build_product_card
from usr.views.stock.dialogs import build_producto_historial_dialog

logger = get_logger(__name__)

class StockView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        
        # Estado interno
        self.is_loading = False
        self._conn_check_active = False
        self.current_almacen_filter = ""
        self.current_categoria_filter = ""
        self.current_search_text = ""
        self.current_stock_filter = "all"
        
        # Componentes UI persistentes
        self.categoria_filter = None
        self.almacen_filter = None
        self.search_field = None
        self.productos_list = None
        self.summary_container = None
        self.total_productos_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD)
        self.stock_bajo_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD)
        self.sin_stock_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD)
        self.active_dialog = None

    def did_mount(self):
        try:
            self._build_ui()
            self.page.run_task(self._initial_load)
            self.page.run_task(self._start_connection_monitor)
            
            from usr.database.sync_callbacks import register_sync_callback
            register_sync_callback(self._on_sync_complete)
        except Exception as e:
            logger.error(f"Error en did_mount de StockView: {e}", exc_info=True)
            show_error("Error al iniciar la vista de Stock", e)

    def will_unmount(self):
        self._conn_check_active = False
        from usr.database.sync_callbacks import unregister_sync_callback
        unregister_sync_callback(self._on_sync_complete)

    async def _initial_load(self):
        try:
            await asyncio.to_thread(self._load_categorias)
            await asyncio.to_thread(self._load_productos)
        except Exception as e:
            logger.error(f"Error en carga inicial de Stock: {e}")
            show_error("No se pudieron cargar los datos de stock", e)

    async def _start_connection_monitor(self):
        self._conn_check_active = True
        while self._conn_check_active:
            await asyncio.sleep(10)
            if self.page and self._conn_check_active:
                try:
                    self._update_connection_indicator()
                    self.page.update()
                except Exception:
                    pass

    def _on_sync_complete(self):
        if hasattr(self, 'page') and self.page and self.visible:
            async def _reload():
                try:
                    await asyncio.to_thread(self._load_productos)
                except Exception as e:
                    logger.error(f"Error recargando stock tras sync: {e}")
            self.page.run_task(_reload)

    def on_sync_complete(self):
        self._on_sync_complete()

    def _on_refresh(self):
        try:
            from usr.database.base import is_online as base_is_online
            from usr.database import get_sync_manager
            
            if base_is_online():
                sync_mgr = get_sync_manager()
                if sync_mgr:
                    sync_mgr.force_sync_now()
            
            show_info("Actualizando stock...", duration=1)
            self.page.run_task(self._refresh_data)
        except Exception as e:
            logger.error(f"Error en _on_refresh de StockView: {e}")
            show_error("Error al refrescar el stock", e)

    async def _refresh_data(self):
        try:
            await asyncio.to_thread(self._load_categorias)
            await asyncio.to_thread(self._load_productos)
            show_success("Stock actualizado")
        except Exception as e:
            logger.error(f"Error en _refresh_data: {e}")
            show_error("Error al actualizar los datos", e)

    async def _on_sync_indicator_click(self, e=None):
        try:
            self._update_connection_indicator()
            if self.page: self.page.update()
        except Exception as e:
            logger.error(f"Error indicador sync: {e}")

    def _update_connection_indicator(self):
        try:
            from usr.database.base import is_online as base_is_online
            from usr.database import get_pending_movimientos_count
            
            if not hasattr(self, '_connection_indicator'): return
            
            pending = get_pending_movimientos_count()
            online = base_is_online()
            
            if online:
                self._connection_indicator.content = ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18)
                self._connection_indicator.tooltip = f"Conectado - {pending} cambios pendientes" if pending else "Conectado"
            else:
                self._connection_indicator.content = ft.Icon(ft.Icons.WIFI_OFF, color=ft.Colors.RED_400, size=18)
                self._connection_indicator.tooltip = f"Modo offline - {pending} cambios pendientes"
            
            self._connection_indicator.update()
        except Exception as e:
            logger.error(f"Error actualizando indicador: {e}")

    def on_theme_change(self):
        if not self.page: return
        try:
            self._build_ui()
            self._load_categorias()
            self._load_productos()
        except Exception as e:
            logger.error(f"Error en on_theme_change de StockView: {e}")

    def _build_ui(self):
        colors = get_safe_colors(self.page)
        self.bgcolor = colors['bg']
        
        self._connection_indicator = ft.Container(
            content=ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18),
            tooltip="Conectado",
            padding=5,
            on_click=self._on_sync_indicator_click
        )
        
        header = ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Text("Gestión de Stock", size=24, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                    ft.Text("Control e inventario de productos y pesaje", size=14, color=colors['text_secondary']),
                ], spacing=2, expand=True),
                self._connection_indicator,
                ft.IconButton(
                    icon=ft.Icons.REFRESH_ROUNDED,
                    icon_color=colors['text_secondary'],
                    on_click=lambda _: self._on_refresh(),
                    tooltip="Recargar datos"
                )
            ]),
            padding=ft.padding.symmetric(horizontal=16, vertical=12)
        )
        
        self.summary_container = ft.Container(
            content=ft.Row([
                build_stat_card("Total", self.total_productos_text, ft.Icons.INVENTORY_2, '#2196F3', 
                                on_click=lambda _: self._filter_by_stock_status("all"), active=(self.current_stock_filter == "all")),
                build_stat_card("Bajo Stock", self.stock_bajo_text, ft.Icons.WARNING_AMBER, '#FF9800', 
                                on_click=lambda _: self._filter_by_stock_status("low"), active=(self.current_stock_filter == "low")),
                build_stat_card("Agotado", self.sin_stock_text, ft.Icons.ERROR_OUTLINE, '#F44336', 
                                on_click=lambda _: self._filter_by_stock_status("out"), active=(self.current_stock_filter == "out")),
            ], scroll=ft.ScrollMode.HIDDEN, spacing=12),
            padding=ft.padding.symmetric(horizontal=16),
            clip_behavior=ft.ClipBehavior.HARD_EDGE,
            animate_size=ft.Animation(220, ft.AnimationCurve.EASE_OUT),
            animate_opacity=ft.Animation(220, ft.AnimationCurve.EASE_OUT),
        )
        
        self.search_field = ft.TextField(
            label="Buscar producto...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=12,
            border_color=colors['input_border'],
            focused_border_color=colors['accent'],
            on_change=self._filter_productos,
        )
        
        self.categoria_filter = ft.Dropdown(
            label="Categoría",
            border_radius=12,
            border_color=colors['input_border'],
            on_change=self._filter_productos,
        )
        
        self.almacen_filter = ft.Dropdown(
            label="Almacén",
            border_radius=12,
            border_color=ft.Colors.TRANSPARENT,
            on_change=self._filter_productos,
            value=""
        )
        
        self.filters_section = ft.Container(
            content=ft.ResponsiveRow([
                ft.Column([self.search_field], col={"xs": 12, "sm": 6}),
                ft.Column([self.categoria_filter], col={"xs": 6, "sm": 3}),
                ft.Column([self.almacen_filter], col={"xs": 6, "sm": 3}),
            ], spacing=12),
            padding=ft.padding.symmetric(horizontal=16, vertical=4),
            clip_behavior=ft.ClipBehavior.HARD_EDGE,
            animate_size=ft.Animation(220, ft.AnimationCurve.EASE_OUT),
            animate_opacity=ft.Animation(220, ft.AnimationCurve.EASE_OUT),
        )
        self.filters_spacer = ft.Container(height=8, animate_size=ft.Animation(220, ft.AnimationCurve.EASE_OUT))
        
        self.productos_list = ft.Column(
            spacing=12,
        )
        
        self.list_container = ft.Container(
            content=self.productos_list,
            bgcolor=colors['bg'],
            padding=ft.padding.only(left=16, right=16, bottom=20),
        )
        
        # Toda la vista se desplaza junta: el encabezado (Gestión de Stock + resumen +
        # filtros) se oculta naturalmente al hacer scroll, sin saltos.
        self.content = ft.Column([
            header,
            self.summary_container,
            self.filters_spacer,
            self.filters_section,
            self.list_container,
        ], spacing=0, expand=True, scroll=ft.ScrollMode.AUTO)
        self.content.bgcolor = colors['bg']

    def _load_categorias(self):
        try:
            categorias = load_categories()
            self.categoria_filter.options = [ft.dropdown.Option("", "Todas")]
            for cat in categorias:
                self.categoria_filter.options.append(ft.dropdown.Option(str(cat.id), cat.nombre))
            
            almacenes = load_warehouses()
            self.almacen_filter.options = [ft.dropdown.Option("", "Todos")]
            for a in almacenes:
                self.almacen_filter.options.append(ft.dropdown.Option(a[0], a[0].capitalize()))
            
            if self.page and self.visible:
                self.update()
        except Exception as e:
            logger.error(f"Error cargando categorías stock: {e}")
            show_error("Error al cargar categorías", e)

    def _load_productos(self):
        if self.is_loading:
            return
        
        self.is_loading = True
        colors = get_safe_colors(self.page)

        if hasattr(self, 'list_container'):
            self.list_container.content = ft.Container(
                content=ft.Column([
                    ft.ProgressRing(color=colors['accent']),
                    ft.Text("Cargando productos...", size=14, color=colors['text_secondary']),
                ], horizontal_alignment="center", spacing=10),
                alignment=ft.alignment.center,
                bgcolor=colors['bg'],
                expand=True,
            )
            if self.page and self.visible:
                self.update()

        try:
            productos = load_products()
            producto_ids = [p.id for p in productos]
            existencias_map = get_existencias_map(producto_ids)
            self._render_productos(productos, existencias_map)
        except Exception as e:
            logger.error(f"Error cargando productos stock: {e}")
            show_error("Error al cargar productos", e)
        finally:
            self.is_loading = False

    def _filter_productos(self, e=None):
        if hasattr(self, '_debounce_task') and self._debounce_task and not self._debounce_task.done():
            self._debounce_task.cancel()
        self._debounce_task = self.page.run_task(self._buscar_async)

    async def _buscar_async(self):
        await asyncio.sleep(0.4)
        try:
            search = self.search_field.value.strip() if self.search_field.value else ""
            categoria = self.categoria_filter.value if self.categoria_filter.value else ""
            almacen = self.almacen_filter.value if self.almacen_filter.value else ""
            
            productos, existencias_map = filter_products_db(
                search, categoria, almacen, stock_status=self.current_stock_filter
            )
            self._render_productos(productos, existencias_map)
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"Error en búsqueda de stock: {e}")
            show_error("Error al filtrar productos", e)

    def _render_productos(self, productos, existencias_map=None):
        if existencias_map is None:
            existencias_map = {}

        colors = get_safe_colors(self.page)

        if hasattr(self, 'list_container') and self.list_container.content is not self.productos_list:
            self.list_container.content = self.productos_list

        total = len(productos)
        bajo = 0
        sin_stock = 0
        for p in productos:
            stock_actual = sum(existencias_map.get(p.id, {}).values()) or 0
            stock_minimo = p.stock_minimo or 0
            if stock_actual <= 0:
                sin_stock += 1
            elif stock_actual <= stock_minimo:
                bajo += 1
        self.total_productos_text.value = str(total)
        self.stock_bajo_text.value = str(bajo)
        self.sin_stock_text.value = str(sin_stock)

        self.productos_list.controls.clear()
        
        if not productos:
            self.productos_list.controls.append(ft.Text("No se encontraron productos", color=colors['text_secondary'], text_align="center"))
        else:
            db = next(get_db_adaptive())
            try:
                rows = []
                per_row = 1 if (self.page and self.page.width and self.page.width < 720) else 2
                current_row = ft.Row(spacing=12, alignment=ft.MainAxisAlignment.START)
                
                for i, p in enumerate(productos):
                    stock_por_almacen = existencias_map.get(p.id, {})
                    stock_actual = sum(stock_por_almacen.values()) or 0
                    
                    if stock_actual <= 0: color = colors['error']
                    elif stock_actual <= (p.stock_minimo or 0): color = colors['warning']
                    else: color = colors['success']

                    es_pesable = getattr(p, 'es_pesable', False)
                    
                    if es_pesable:
                        peso_entrada = db.query(func.sum(Movimiento.peso_total)).filter(
                            Movimiento.producto_id == p.id, Movimiento.tipo == "entrada"
                        ).scalar() or 0.0
                        
                        peso_salida = db.query(func.sum(Movimiento.peso_total)).filter(
                            Movimiento.producto_id == p.id, Movimiento.tipo == "salida"
                        ).scalar() or 0.0
                        
                        peso_neto = peso_entrada - peso_salida
                    else:
                        peso_neto = 0
                    
                    card = build_product_card(
                        p, stock_actual, color, stock_por_almacen, peso_neto, colors,
                        on_action=lambda action, prod: self._handle_product_action(action, prod)
                    )
                    card.expand = True # ancho completo (1 columna en móvil, 2 iguales en escritorio)
                    
                    current_row.controls.append(card)
                    
                    if len(current_row.controls) == per_row:
                        rows.append(current_row)
                        current_row = ft.Row(spacing=12, alignment=ft.MainAxisAlignment.START)
                
                if current_row.controls:
                    rows.append(current_row)
                
                self.productos_list.controls.extend(rows)
            finally:
                db.close()
        
        if self.page and self.visible:
            self.update()

    def _show_producto_details(self, producto: Producto):
        try:
            from usr.views.stock.dialogs import build_producto_historial_dialog
            
            movimientos = get_producto_historial(producto.id, limit=20)
            
            self.active_dialog = build_producto_historial_dialog(producto, movimientos)
            self.active_dialog.actions[0].on_click = self._close_dialog
            
            self.page.overlay.append(self.active_dialog)
            self.active_dialog.open = True
            self.page.update()
        except Exception as e:
            logger.error(f"Error historial stock: {e}", exc_info=True)
            show_error("Error al abrir historial", e)

    def _close_dialog(self, e=None):
        if self.active_dialog:
            self.active_dialog.open = False
            if self.page and self.visible:
                self.page.update()
            self.active_dialog = None

    def _handle_product_action(self, action, producto):
        if action == "historial":
            self._show_producto_details(producto)
        elif action == "existencias":
            self._show_existencias(producto)

    def _show_existencias(self, producto: Producto):
        try:
            from usr.views.stock.dialogs import build_existencias_dialog, build_ajuste_dialog
            from usr.views.stock.data import get_existencias_producto
            from usr.views.inventario.movements import ajustar_existencia
            from usr.database.local_replica import LocalReplica

            # Limpiar posibles duplicados (conserva el ajuste más reciente)
            LocalReplica.dedupe_existencias_producto(producto.id)

            existencias = get_existencias_producto(producto.id)

            def _on_ajustar(almacen, cantidad_actual, unidad):
                def _on_confirm(nueva, motivo):
                    ok = ajustar_existencia(self.page, producto, almacen, nueva, motivo)
                    if ok:
                        self._close_dialog()
                        # Refrescar la lista de productos (el stock puede cambiar)
                        self.page.run_task(self._buscar_async)
                        # Reabrir el panel de existencias con los valores actualizados
                        self._show_existencias(producto)

                def _on_cancel(e):
                    self._close_dialog()

                ajuste = build_ajuste_dialog(producto, almacen, cantidad_actual, unidad, _on_confirm, _on_cancel)
                self.active_dialog = ajuste
                self.page.overlay.append(ajuste)
                ajuste.open = True
                self.page.update()

            def _on_close(e):
                self._close_dialog()

            self.active_dialog = build_existencias_dialog(producto, existencias, _on_ajustar, _on_close)
            self.page.overlay.append(self.active_dialog)
            self.active_dialog.open = True
            self.page.update()
        except Exception as e:
            logger.error(f"Error existencias: {e}", exc_info=True)
            show_error("Error al abrir existencias", e)

    def _filter_by_stock_status(self, status):
        self.current_stock_filter = status
        self.summary_container.content = ft.Row([
            build_stat_card("Total", self.total_productos_text, ft.Icons.INVENTORY_2, '#2196F3', 
                            on_click=lambda _: self._filter_by_stock_status("all"), active=(self.current_stock_filter == "all")),
            build_stat_card("Bajo Stock", self.stock_bajo_text, ft.Icons.WARNING_AMBER, '#FF9800', 
                            on_click=lambda _: self._filter_by_stock_status("low"), active=(self.current_stock_filter == "low")),
            build_stat_card("Agotado", self.sin_stock_text, ft.Icons.ERROR_OUTLINE, '#F44336', 
                            on_click=lambda _: self._filter_by_stock_status("out"), active=(self.current_stock_filter == "out")),
        ], scroll=ft.ScrollMode.HIDDEN, spacing=12)
        if self.page and self.visible:
            self.summary_container.update()
        self.page.run_task(self._buscar_async)
