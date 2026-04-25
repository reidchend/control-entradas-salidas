import flet as ft
import asyncio
from usr.database.base import get_db, get_db_adaptive
from usr.models import Producto, Movimiento, Categoria, Existencia, Factura
from datetime import datetime
import logging
from sqlalchemy import func
from usr.theme import get_theme, get_colors

logger = logging.getLogger(__name__)


def _colors(page):
    return get_colors(page)

class StockView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.bgcolor = '#1A1A1A'
        self.padding = ft.padding.all(0)
        
        colors = _colors(None)  # Default for __init__
        
        # Componentes UI
        self.categoria_filter = None
        self.almacen_filter = None
        self.search_field = None
        self.productos_list = None
        self.summary_container = None
        self.active_dialog = None
        self.is_loading = False
        
        # Estado de resumen
        self.total_productos_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD, color=colors['accent'])
        self.stock_bajo_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD, color=colors['warning'])
        self.sin_stock_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD, color=colors['error'])

    def did_mount(self):
        self._build_ui()
        if self.page and self.page.client_storage:
            self._load_categorias()
            self._load_productos()
        
        self._update_connection_indicator()
        
        # Registrar callback para sync automático
        from usr.database.sync_callbacks import register_sync_callback
        register_sync_callback(self._on_sync_complete)
        
        import threading
        import time
        
        def check_connection_loop():
            while True:
                time.sleep(10)
                if hasattr(self, 'page') and self.page:
                    self._update_connection_indicator()
                    try:
                        self.page.update()
                    except:
                        pass
        
        self._connection_thread = threading.Thread(target=check_connection_loop, daemon=True)
        self._connection_thread.start()
    
    def _on_sync_complete(self):
        """Callback que se ejecuta después de cada sync automático."""
        if hasattr(self, 'page') and self.page and self.visible:
            self.page.run_task(self._load_productos)
    
    def on_sync_complete(self):
        """Alias para compatibilidad con SyncManager callback."""
        self._on_sync_complete()

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
        
        colors = _colors(self.page)
        snack = ft.SnackBar(
            content=ft.Text("🔄 Actualizando..."),
            bgcolor=colors['accent'],
            duration=1,
        )
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()
        self._load_categorias()
        self._load_productos()
        snack = ft.SnackBar(
            content=ft.Text("✓ Datos actualizados"),
            bgcolor=colors['success'],
            duration=2,
        )
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()
    
    async def _on_sync_indicator_click(self, e=None):
        """Solo actualiza el indicador visual"""
        from usr.database import get_sync_manager
        
        sync_mgr = get_sync_manager()
        if not sync_mgr or not self.page:
            return
        
        self._update_connection_indicator()
        self.page.update()
    
    def _show_snack_bar(self, message, bgcolor):
        """Muestra SnackBar."""
        if not self.page:
            return
        snack = ft.SnackBar(
            content=ft.Text(message, weight=ft.FontWeight.BOLD),
            bgcolor=bgcolor,
            duration=5,
        )
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()
    
    def _update_connection_indicator(self):
        from usr.database.base import is_online as base_is_online
        from usr.database import get_pending_movimientos_count
        
        if not hasattr(self, '_connection_indicator'):
            return
        
        pending = get_pending_movimientos_count()
        
        online = base_is_online()
        
        if online:
            self._connection_indicator.content = ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18)
            self._connection_indicator.tooltip = f"Conectado - {pending} cambios pendientes" if pending else "Conectado"
        else:
            self._connection_indicator.content = ft.Icon(ft.Icons.WIFI_OFF, color=ft.Colors.RED_400, size=18)
            self._connection_indicator.tooltip = f"Modo offline - {pending} cambios pendientes"
        
        self._connection_indicator.update()

    def on_theme_change(self):
        """Se llama cuando cambia el tema"""
        if not self.page or not self.page.client_storage:
            return
        colors = _colors(self.page)
        self.bgcolor = colors['bg']
        try:
            self._build_ui()
            if hasattr(self, 'list_container') and self.list_container:
                self.list_container.bgcolor = colors['bg']
            self._load_categorias()
            self._load_productos()
        except:
            pass

    def _build_ui(self):
        colors = _colors(self.page)
        
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
                self._build_stat_card("Total", self.total_productos_text, ft.Icons.INVENTORY_2, '#2196F3'),
                self._build_stat_card("Bajo Stock", self.stock_bajo_text, ft.Icons.WARNING_AMBER, '#FF9800'),
                self._build_stat_card("Agotado", self.sin_stock_text, ft.Icons.ERROR_OUTLINE, '#F44336'),
            ], scroll=ft.ScrollMode.HIDDEN, spacing=12),
            padding=ft.padding.symmetric(horizontal=16)
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

        filters_section = ft.Container(
            content=ft.ResponsiveRow([
                ft.Column([self.search_field], col={"xs": 12, "md": 6}),
                ft.Column([self.categoria_filter], col={"xs": 12, "md": 3}),
                ft.Column([self.almacen_filter], col={"xs": 12, "md": 3}),
            ], spacing=12),
            padding=ft.padding.symmetric(horizontal=16, vertical=8),
        )

        self.productos_list = ft.ListView(
            expand=True,
            spacing=12,
            padding=ft.padding.only(left=16, right=16, bottom=80),
        )

        self.list_container = ft.Container(
            content=self.productos_list,
            expand=True,
            bgcolor=colors['bg'],
        )

        self.content = ft.Column([
            header,
            self.summary_container,
            ft.Container(height=8),
            filters_section,
            self.list_container,
        ], spacing=0, expand=True)
        self.content.bgcolor = colors['bg']

    def _build_stat_card(self, title, value_control, icon, color):
        colors = _colors(self.page)
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

    def _load_categorias(self):
        db = next(get_db_adaptive())
        try:
            categorias = db.query(Categoria).filter(Categoria.activo == True).all()
            self.categoria_filter.options = [ft.dropdown.Option("", "Todas")]
            for cat in categorias:
                self.categoria_filter.options.append(ft.dropdown.Option(str(cat.id), cat.nombre))
            
            almacenes = db.query(Existencia.almacen).distinct().all()
            self.almacen_filter.options = [ft.dropdown.Option("", "Todos")]
            for a in almacenes:
                self.almacen_filter.options.append(ft.dropdown.Option(a[0], a[0].capitalize()))
            
            self.update()
        finally:
            db.close()

    def _load_productos(self):
        if self.is_loading:
            return

        self.is_loading = True

        colors = _colors(self.page)

        # Mostrar spinner reemplazando el contenido del container — cubre todo el área con bgcolor correcto
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
            self.update()

        db = next(get_db_adaptive())
        try:
            productos = db.query(Producto).filter(Producto.activo == True).order_by(Producto.nombre).limit(50).all()
            
            producto_ids = [p.id for p in productos]
            existencias_map = self._get_existencias_map(producto_ids)
            
            self._render_productos(productos, existencias_map)
        finally:
            self.is_loading = False
            db.close()

    def _get_existencias_map(self, producto_ids):
        if not producto_ids:
            return {}
        
        db = next(get_db_adaptive())
        existencias_map = {}
        try:
            existencias = db.query(Existencia.producto_id, Existencia.almacen, Existencia.cantidad).filter(Existencia.producto_id.in_(producto_ids)).all()
            for e in existencias:
                if e.producto_id not in existencias_map:
                    existencias_map[e.producto_id] = {}
                existencias_map[e.producto_id][e.almacen] = e.cantidad
        finally:
            db.close()
        return existencias_map

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
            
            db = next(get_db_adaptive())
            try:
                query = db.query(Producto).filter(Producto.activo == True)
                
                if categoria and categoria.isdigit():
                    query = query.filter(Producto.categoria_id == int(categoria))
                
                if search:
                    query = query.filter((Producto.nombre.ilike(f"%{search}%")) | (Producto.codigo.ilike(f"%{search}%")))
                
                productos = query.order_by(Producto.nombre).limit(50).all()
                
                producto_ids = [p.id for p in productos]
                existencias_map = self._get_existencias_map(producto_ids)
                
                if almacen:
                    productos = [p for p in productos if (existencias_map.get(p.id, {}).get(almacen) or 0) > 0]
                
                self._render_productos(productos, existencias_map)
            finally:
                db.close()
        except asyncio.CancelledError:
            pass

    def _render_productos(self, productos, existencias_map=None):
        if existencias_map is None:
            existencias_map = {}

        colors = _colors(self.page)

        # Restaurar el ListView en el container (reemplaza el spinner)
        if hasattr(self, 'list_container') and self.list_container.content is not self.productos_list:
            self.list_container.content = self.productos_list

        self.total_productos_text.value = str(len(productos))
        self.stock_bajo_text.value = str(sum(1 for p in productos if 0 < (p.stock_actual or 0) <= (p.stock_minimo or 0)))
        self.sin_stock_text.value = str(sum(1 for p in productos if (p.stock_actual or 0) <= 0))

        self.productos_list.controls.clear()
        
        if not productos:
            self.productos_list.controls.append(ft.Text("No se encontraron productos", color=colors['text_secondary'], text_align="center"))
        else:
            db = next(get_db_adaptive())
            try:
                for p in productos:
                    stock_por_almacen = existencias_map.get(p.id, {})
                    stock_actual = sum(stock_por_almacen.values()) or 0
                    
                    if stock_actual <= 0: color = colors['error']
                    elif stock_actual <= (p.stock_minimo or 0): color = colors['warning']
                    else: color = colors['success']

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

                    peso_view = ft.Container()
                    es_pesable = getattr(p, 'es_pesable', False)
                    
                    if es_pesable:
                        peso_entrada = db.query(func.sum(Movimiento.peso_total)).filter(
                            Movimiento.producto_id == p.id, Movimiento.tipo == "entrada"
                        ).scalar() or 0.0
                        
                        peso_salida = db.query(func.sum(Movimiento.peso_total)).filter(
                            Movimiento.producto_id == p.id, Movimiento.tipo == "salida"
                        ).scalar() or 0.0
                        
                        peso_neto = peso_entrada - peso_salida
                        
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

                    self.productos_list.controls.append(
                        ft.Container(
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
                                            on_click=lambda e, prod=p: self._show_producto_details(prod)
                                        )
                                    ])
                                ], alignment="spaceBetween")
                            ], spacing=8),
                            padding=16, 
                            bgcolor=colors['card'], 
                            border_radius=12, 
                            border=ft.border.all(1, colors['border']),
                        )
                    )
            finally:
                db.close()
        
        if self.page:
            self.update()

    def _show_producto_details(self, producto: Producto):
        colors = _colors(self.page)
        db = next(get_db_adaptive())
        try:
            movimientos = db.query(Movimiento).filter(Movimiento.producto_id == producto.id).order_by(Movimiento.fecha_movimiento.desc()).limit(20).all()
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
                
                # Número de factura si existe (sin fondo, del mismo tamaño que el tipo)
                factura_texto = ""
                if m.factura_id:
                    factura = db.query(Factura).filter(Factura.id == m.factura_id).first()
                    if factura:
                        factura_texto = f" - 📄 {factura.numero_factura}"
                
                # Contenedor Principal (Más flexible que ListTile)
                mov_list.controls.append(
                    ft.Container(
                        content=ft.Row(
                            [
                                # Icono
                                ft.Container(
                                    content=ft.Icon(icon, color=color, size=24),
                                    padding=ft.padding.only(right=10)
                                ),
                                # Contenido central (Tipo, cantidad y factura)
                                ft.Column(
                                    [
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
                                # Cantidad (Alineado a la derecha)
                                ft.Text(
                                    f"{'+' if is_entrada else '-'}{cantidad_valor:.3f}" if es_pesable and (m.peso_total or 0) > 0 else f"{'+' if is_entrada else '-'}{int(cantidad_valor)}", 
                                    color=color, 
                                    weight="bold",
                                    size=16
                                ),
                            ],
                            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                        ),
                        bgcolor=colors['bg'],
                        padding=15,
                        border_radius=10,
                        margin=ft.margin.only(bottom=8),
                    )
                )

            self.active_dialog = ft.AlertDialog(
                title=ft.Text(f"Historial: {producto.nombre}"),
                content=ft.Column([ft.Divider(), mov_list], tight=True, width=450),
                actions=[ft.TextButton("Cerrar", on_click=self._close_dialog)],
            )
            self.page.overlay.append(self.active_dialog)
            self.active_dialog.open = True
            self.page.update()
        except Exception as e:
            logger.error(f"Error historial: {e}")
        finally:
            db.close()

    def _close_dialog(self, e=None):
        if self.active_dialog:
            self.active_dialog.open = False
            self.page.update()
    
    def _show_factura_details(self, factura: Factura):
        """Muestra los detalles de la factura en un dialog."""
        colors = _colors(self.page)
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Text(f"📄 Factura: {factura.numero_factura}"),
            content=ft.Column([
                ft.Divider(),
                ft.Row([
                    ft.Column([
                        ft.Text("Proveedor", size=12, color=colors.get('text_secondary', '#888')),
                        ft.Text(factura.proveedor or "N/A", weight="bold"),
                    ], spacing=2, expand=1),
                    ft.Column([
                        ft.Text("Fecha Factura", size=12, color=colors.get('text_secondary', '#888')),
                        ft.Text(factura.fecha_factura or "N/A", weight="bold"),
                    ], spacing=2, expand=1),
                ], spacing=20),
                ft.Divider(),
                ft.Row([
                    ft.Column([
                        ft.Text("Total Neto", size=12, color=colors.get('text_secondary', '#888')),
                        ft.Text(f"${factura.total_neto:,.2f}" if factura.total_neto else "$0.00", weight="bold", size=16),
                    ], spacing=2),
                ]),
                ft.Divider(),
                ft.Text(f"Estado: {factura.estado}", weight="bold", color=colors.get('success', '#4CAF50')),
            ], tight=True),
            actions=[ft.TextButton("Cerrar", on_click=self._close_dialog)],
        )
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()