import flet as ft
import asyncio
import hashlib
import threading
from datetime import datetime
from usr.database.base import get_db, get_db_adaptive, is_online
from usr.database.local_replica import LocalReplica
from usr.models import Categoria, Producto, Movimiento, Existencia
from usr.logger import get_logger
from usr.theme import get_theme, get_colors
import traceback
from usr.error_handler import show_error
from usr.notifications import show_success, show_error as show_error_notif


def _generar_color(texto):
    hash_hcl = hashlib.md5(texto.encode()).hexdigest()
    return f"#{hash_hcl[:6]}"


def _get_attr(obj, key, default=""):
    """Obtiene atributo de forma segura - maneja dict u objeto"""
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)


def _colors(page):
    return get_colors(page)


def _get_safe_colors(page):
    """Obtiene colores de forma segura, evita problemas cuando page no está disponible"""
    if page and hasattr(page, 'theme_mode'):
        return get_theme(page.theme_mode == ft.ThemeMode.DARK)
    return get_theme(True)

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
        
        self.categorias_grid = ft.GridView(
            expand=True,
            runs_count=5,
            max_extent=120,
            child_aspect_ratio=0.8,
            spacing=10,
            run_spacing=10,
        )

        self.main_content_area = ft.Container(
            content=self.categorias_grid,
            expand=True,
        )
        
        self._vista_requisicion_activa = False
        self.panel_requisicion = None
        self.lista_requisicion = []
        self._productos_req = []

        self.categoria_seleccionada = None
        self.producto_seleccionado = None
        self._is_initialized = False
        self._categorias_cache = None
        self._productos_cache = None
        self._existencias_cache = None
        self._snack = None
        self._search_timer = None  # Para debounce de búsqueda

        self._build_ui()

    def on_theme_change(self):
        """Se llama cuando cambia el tema"""
        if not self.page:
            return

        colors = _get_safe_colors(self.page)
        self.bgcolor = colors['bg']

        if hasattr(self, 'main_content_area'):
            self.main_content_area.bgcolor = colors['surface']

        if hasattr(self, 'search_field') and self.search_field:
            self.search_field.border_color = colors['input_border']
            self.search_field.focused_border_color = colors['accent']

        if hasattr(self, 'header_container'):
            self._build_ui()

        # Redibujar cards desde caché usando los nuevos colores del tema,
        # sin necesidad de ir a la BD
        if hasattr(self, 'categorias_grid') and not self.categoria_seleccionada:
            if self._categorias_cache:
                # Determinar si el caché contiene objetos ORM o dicts
                if isinstance(self._categorias_cache[0], dict):
                    self.categorias_grid.controls = [
                        self._create_categoria_card_from_dict(c)
                        for c in self._categorias_cache
                    ]
                else:
                    self.categorias_grid.controls = [
                        self._create_categoria_card(c)
                        for c in self._categorias_cache
                    ]
                self.categorias_grid.update()
            else:
                # Sin caché: carga desde BD como último recurso
                self.page.run_task(self._load_categorias)

    def did_mount(self):
        """Se ejecuta cuando el control se añade a la página."""
        if not self._is_initialized:
            if self.page:
                self.page.run_task(self._load_categorias)
            self._is_initialized = True
        
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
                    except Exception as e:
                        show_error("Error updating page", e, "inventario_view.check_connection_loop")
        
        self._connection_thread = threading.Thread(target=check_connection_loop, daemon=True)
        self._connection_thread.start()
    
    def will_unmount(self):
        """Se ejecuta cuando el control se移除 de la página."""
        from usr.database.sync_callbacks import unregister_sync_callback
        unregister_sync_callback(self._on_sync_complete)
    
    def _on_sync_complete(self):
        """Callback que se ejecuta después de cada sync automático."""
        if hasattr(self, 'page') and self.page and self.visible:
            self.page.run_task(self._load_categorias)
    
    def on_sync_complete(self):
        """Alias para compatibilidad con SyncManager callback."""
        self._on_sync_complete()

    def _build_ui(self):
        try:
            colors = _get_safe_colors(self.page)
            
            self._connection_indicator = ft.Container(
                content=ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18),
                tooltip="Conectado",
                padding=5,
                on_click=self._on_sync_indicator_click
            )
            
            self.header_container = ft.Container(
                content=ft.Row([
                    ft.Column([
                        ft.Text("Inventario", size=22, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                        ft.Text("Gestión de existencias", size=12, color=colors['text_secondary']),
                    ], expand=True, spacing=0),
                    ft.Container(),
                    self._connection_indicator,
                    ft.IconButton(
                        icon=ft.Icons.REFRESH_ROUNDED,
                        on_click=lambda _: self._on_refresh(),
                        tooltip="Recargar desde BD",
                        icon_color=colors['text_secondary'],
                    )
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                margin=ft.margin.only(bottom=10)
            )

            self.search_field = ft.TextField(
                hint_text="Buscar...",
                prefix_icon=ft.Icons.SEARCH_ROUNDED,
                border_radius=12,
                border_color=colors['input_border'],
                focused_border_color=colors['accent'],
                height=45,
                text_size=14,
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
        """Refresca datos - hace sync solo si está online"""
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
        elif self._vista_requisicion_activa:
            pass
        
        self.page.overlay.clear()
        snack = ft.SnackBar(
            content=ft.Text("🔄 Actualizando..."),
            bgcolor=ft.Colors.BLUE_600,
            duration=1,
        )
        self.page.overlay.clear()
        snack = ft.SnackBar(
            content=ft.Text("🔄 Actualizando..."),
            bgcolor=ft.Colors.BLUE_600,
            duration=1,
        )
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()
    
    async def _on_sync_indicator_click(self, e=None):
        """Solo actualiza el indicador visual"""
        from usr.database import get_sync_manager, get_pending_movimientos_count
        
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
        """Actualiza el indicador de conexión."""
        from usr.database import base, get_sync_manager, get_pending_movimientos_count
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
        except Exception as e:
            show_error("Error updating connection indicator", e, "inventario_view._update_connection_indicator")

    async def _load_categorias(self, force_refresh=False):
        if not self.page:
            return

        try:
            local_categorias = LocalReplica.get_categorias()
            
            if local_categorias:
                self._categorias_cache = local_categorias
                self.categorias_grid.controls = [
                    self._create_categoria_card_from_dict(c) for c in local_categorias
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
                            self._create_categoria_card_from_dict(c) for c in cats_data
                        ]
                        self.update()
                        
                        if self.page:
                            snack = ft.SnackBar(
                                content=ft.Text("✓ Datos actualizados desde servidor"),
                                bgcolor=ft.Colors.GREEN_700,
                                duration=2,
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



    async def _handle_category_click(self, container, categoria):
        """Maneja la animación y el cambio de vista."""
        try:
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

    def _get_card_bg(self):
        """Retorna el color de fondo según el tema"""
        if self.page and self.page.theme_mode == ft.ThemeMode.LIGHT:
            return '#F0F4F8'
        return '#2D2D2D'

    def _create_categoria_card(self, categoria):
        nombre = getattr(categoria, 'nombre', '') or 'SIN NOMBRE'
        cat_color = getattr(categoria, 'color', None) or '#00FF00'
        inicial = nombre[0].upper() if nombre else "?"
        
        # 1. Contenido de la tarjeta (Círculo + Texto)
        content_col = ft.Column(
            [
                ft.Container(
                    content=ft.Text(inicial, size=22, weight="bold", color=ft.Colors.WHITE),
                    width=45, height=45, bgcolor=cat_color,
                    border_radius=25, alignment=ft.alignment.center,
                ),
                ft.Text(nombre.upper(), size=10, weight="bold", color=ft.Colors.WHITE, text_align="center"),
            ],
            horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            spacing=5,
        )
        
        # 2. Contenedor principal (Garantizando tamaño y colores)
        card = ft.Container(
            content=content_col,
            bgcolor='#2D2D2D',
            width=110,
            height=130,
            border_radius=12,
            padding=10,
            border=ft.border.only(bottom=ft.BorderSide(4, cat_color)),
        )
        
        card.on_click = lambda e: self._show_productos(categoria)
        return card

    def _al_pasar_mouse(self, e, card, cat_color):
        """Efecto profesional: Escala + Rotación + Sombra progresiva con color de categoría"""
        if e.data == "true":
            card.scale = 1.05
            card.rotate = 0.02
            card.shadow = ft.BoxShadow(
                blur_radius=15,
                color=ft.Colors.with_opacity(0.2, cat_color),
                offset=ft.Offset(0, 0),
            )
            card.animate = ft.Animation(300, ft.AnimationCurve.DECELERATE)
        else:
            card.scale = 1.0
            card.rotate = 0
            card.shadow = ft.BoxShadow(
                blur_radius=0,
                color=ft.Colors.with_opacity(0.1, cat_color),
                offset=ft.Offset(0, 0),
            )
            card.animate = ft.Animation(300, ft.AnimationCurve.DECELERATE)
        card.update()

    def _create_categoria_card_from_dict(self, cat_dict):
        """Crea tarjeta de categoría desde diccionario (caché)"""
        nombre = cat_dict.get("nombre", "")
        cat_color = cat_dict.get("color") or _generar_color(nombre)
        inicial = nombre[0].upper() if nombre else "?"

        colors = _get_safe_colors(self.page)
        card_bg = colors['card']
        text_color = colors['text_primary']
        text_secondary = colors['text_secondary']

        card = ft.Container(
            bgcolor=card_bg,
            border_radius=12,
            padding=12,
            width=110,
            height=130,
            alignment=ft.alignment.center,
            border=ft.border.only(bottom=ft.BorderSide(3, cat_color)),
            shadow=ft.BoxShadow(
                blur_radius=0,
                color=ft.Colors.with_opacity(0.2, cat_color),
                offset=ft.Offset(0, 3),
            ),
            animate_scale=ft.Animation(400, ft.AnimationCurve.DECELERATE),
            animate_rotation=ft.Animation(400, ft.AnimationCurve.DECELERATE),
            content=ft.Column(
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                alignment=ft.MainAxisAlignment.CENTER,
                controls=[
                    ft.Container(
                        content=ft.Text(inicial, size=20, weight="bold", color=ft.Colors.WHITE),
                        alignment=ft.alignment.center,
                        width=40,
                        height=40,
                        bgcolor=cat_color,
                        shape=ft.BoxShape.CIRCLE,
                        shadow=ft.BoxShadow(
                            blur_radius=8,
                            color=ft.Colors.with_opacity(0.3, cat_color),
                            offset=ft.Offset(0, 3)
                        )
                    ),
                    ft.Container(height=8),
                    ft.Text(
                        str(nombre).upper(),
                        size=10,
                        weight="bold",
                        color=text_color,
                        text_align=ft.TextAlign.CENTER,
                        max_lines=2,
                        overflow=ft.TextOverflow.ELLIPSIS
                    ),
                ]
            )
        )
        card.on_hover = lambda e: self._al_pasar_mouse(e, card, cat_color)
        cat_obj = type('Categoria', (), cat_dict)()
        card.on_click = lambda e: self.page.run_task(self._handle_category_click, card, cat_obj)
        return card

    def _show_productos(self, categoria):
        self.categoria_seleccionada = categoria
        colors = _get_safe_colors(self.page)
        
        if self.search_field:
            self.search_field.visible = False
        
        header_nav = ft.Container(
            content=ft.Row([
                ft.IconButton(
                    ft.Icons.ARROW_BACK_ROUNDED, 
                    on_click=lambda _: self._reset_view(),
                    icon_color=colors['text_secondary']
                ),
                ft.Text(categoria.nombre, size=18, weight="bold", color=colors['text_primary']),
            ]),
            bgcolor=colors['surface'],
            padding=10,
            border_radius=10,
        )
        
        self.productos_list = ft.ListView(expand=True, spacing=10, padding=ft.padding.only(top=10))
        
        self.search_for_products = ft.TextField(
            hint_text="Buscar productos...",
            prefix_icon=ft.Icons.SEARCH_ROUNDED,
            border_radius=12,
            border_color=colors['input_border'],
            focused_border_color=colors['accent'],
            height=45,
            text_size=14,
            on_change=self._on_search_change,
            value="",
        )
        
        nueva_vista = ft.Column([header_nav, self.search_for_products, self.productos_list], expand=True, spacing=5)
        self.main_content_area.content = nueva_vista
        self._load_productos()
        if self.page: self.update()

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
                self._create_categoria_card_from_dict(c) for c in self._categorias_cache
            ]
        if self.page: self.update()

    def _on_search_change(self, e=None):
        """Filtra categorías o productos según el contexto con debounce"""
        if self._search_timer:
            self._search_timer.cancel()
        
        def do_search():
            active_search_field = self.search_for_products if self.categoria_seleccionada else self.search_field
            search_term = active_search_field.value.lower().strip() if active_search_field and active_search_field.value else ""
            
            if self.categoria_seleccionada and hasattr(self, '_productos_cache') and self._productos_cache:
                if not self._productos_cache:
                    return
                if search_term:
                    filtered = [p for p in self._productos_cache if search_term in _get_attr(p, "nombre", "").lower()]
                else:
                    filtered = self._productos_cache
                
                existencias_map = getattr(self, '_existencias_cache', {})
                self.productos_list.controls = [
                    self._create_producto_item_from_dict(p, existencias_map.get(_get_attr(p, "id", 0), {})) 
                    for p in filtered
                ]
            else:
                if not self._categorias_cache or len(self._categorias_cache) == 0:
                    return
                
                if search_term:
                    filtered = [c for c in self._categorias_cache if search_term in _get_attr(c, "nombre", "").lower()]
                else:
                    filtered = self._categorias_cache
                
                if not filtered:
                    colors = _get_safe_colors(self.page)
                    self.categorias_grid.controls = [ft.Text("Sin resultados", size=16, color=colors['text_secondary'])]
                else:
                    self.categorias_grid.controls = [self._create_categoria_card_from_dict(c) for c in filtered]
            
            if self.page:
                self.update()
        
        self._search_timer = threading.Timer(0.3, do_search)
        self._search_timer.start()

    def _load_productos(self, search_term=""):
        if not self.categoria_seleccionada: return
        
        try:
            cat_id = self.categoria_seleccionada.id if hasattr(self.categoria_seleccionada, 'id') else self.categoria_seleccionada.get('id')
            
            local_productos = LocalReplica.get_productos(cat_id)
            local_existencias = LocalReplica.get_existencias()
            
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
            
            items = [self._create_producto_item_from_dict(p, existencias_map.get(p.get("id"), {})) for p in local_productos]
            self.productos_list.controls = items if items else [ft.Text("No hay productos")]
            if self.page: self.update()
        except Exception as e:
            show_error("Error loading products", e, "inventario_view._load_productos_por_categoria")
            logger.error(f"Error carga productos: {e}")

    def _create_producto_item(self, producto, stock_por_almacen=None):
        if stock_por_almacen is None:
            stock_por_almacen = {}
        colors = _get_safe_colors(self.page)
        stock = sum(stock_por_almacen.values()) or 0
        stock_min = producto.stock_minimo or 0
        stock_color = colors['error'] if stock < stock_min else colors['success']
        
        es_pesable = getattr(producto, 'es_pesable', False)
        badge_pesable = ft.Container(
            content=ft.Text("PESABLE", size=9, color='#FFFFFF', weight="bold"),
            bgcolor='#FF9800',
            padding=ft.padding.symmetric(horizontal=4, vertical=1),
            border_radius=3
        ) if es_pesable else ft.Container()

        return ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Row([ft.Text(str(producto.nombre), weight="bold", size=14, color=colors['text_primary']), badge_pesable], spacing=5),
                    ft.Row([
                        ft.Container(
                            content=ft.Text(f"Stock: {stock}", size=10, weight="bold", color='#FFFFFF'),
                            bgcolor=stock_color, padding=ft.padding.symmetric(horizontal=6, vertical=2), border_radius=5
                        ),
                        ft.Text(f"Mín: {stock_min}", size=10, color=colors['text_secondary']),
                    ], spacing=10)
                ], expand=True),
                ft.IconButton(ft.Icons.ADD_CIRCLE_OUTLINE_ROUNDED, icon_color=colors['success'], icon_size=24,
                             on_click=lambda _, p=producto: self._show_cantidad_dialog(p, "entrada")),
                ft.IconButton(ft.Icons.REMOVE_CIRCLE_OUTLINE_ROUNDED, icon_color=colors['error'], icon_size=24,
                             on_click=lambda _, p=producto: self._show_cantidad_dialog(p, "salida")),
            ], spacing=5),
            padding=10, bgcolor=colors['card'], border_radius=10, border=ft.border.all(1, colors['border'])
        )

    def _create_producto_item_from_dict(self, prod_dict, stock_por_almacen=None):
        """Crea item de producto desde diccionario (caché)"""
        if stock_por_almacen is None:
            stock_por_almacen = {}
        colors = _get_safe_colors(self.page)
        stock = sum(stock_por_almacen.values()) or 0
        stock_min = prod_dict.get("stock_minimo", 0) or 0
        stock_color = colors['error'] if stock < stock_min else colors['success']
        
        prod_obj = type('Producto', (), prod_dict)()
        
        return ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Row([ft.Text(str(prod_dict.get("nombre", "")), weight="bold", size=14, color=colors['text_primary'])], spacing=5),
                    ft.Row([
                        ft.Container(
                            content=ft.Text(f"Stock: {stock}", size=10, weight="bold", color='#FFFFFF'),
                            bgcolor=stock_color, padding=ft.padding.symmetric(horizontal=6, vertical=2), border_radius=5
                        ),
                        ft.Text(f"Mín: {stock_min}", size=10, color=colors['text_secondary']),
                    ], spacing=10)
                ], expand=True),
                ft.IconButton(ft.Icons.ADD_CIRCLE_OUTLINE_ROUNDED, icon_color=colors['success'], icon_size=24,
                             on_click=lambda _, p=prod_obj: self._show_cantidad_dialog(p, "entrada")),
                ft.IconButton(ft.Icons.REMOVE_CIRCLE_OUTLINE_ROUNDED, icon_color=colors['error'], icon_size=24,
                             on_click=lambda _, p=prod_obj: self._show_cantidad_dialog(p, "salida")),
            ], spacing=5),
            padding=10, bgcolor=colors['card'], border_radius=10, border=ft.border.all(1, colors['border'])
        )

    def _get_almacenes(self):
        db = next(get_db_adaptive())
        try:
            almacenes = db.query(Existencia.almacen).distinct().all()
            opciones = [a[0] for a in almacenes]
            if "principal" not in opciones:
                opciones.insert(0, "principal")
            return opciones
        finally:
            db.close()

    def _show_cantidad_dialog(self, producto, tipo):
        self.producto_seleccionado = producto
        es_pesable = _get_attr(producto, 'es_pesable', False)
        
        almacen_default = _get_attr(producto, 'almacen_predeterminado', 'principal')
        
        db = next(get_db_adaptive())
        try:
            producto_id = _get_attr(producto, 'id')
            existencias = db.query(Existencia).filter(Existencia.producto_id == producto_id).all()
            stock_por_almacen = {e.almacen: e.cantidad for e in existencias}
            todos_almacenes = db.query(Existencia.almacen).distinct().all()
            almacenes_disponibles = [a[0] for a in todos_almacenes]
            if "principal" not in almacenes_disponibles:
                almacenes_disponibles.append("principal")
        finally:
            db.close()
        
        colors = _get_safe_colors(self.page)
        
        def calcular_desde_unidades(e):
            try:
                cant = float(cant_x_unidad_input.value or 0)
                peso_u_str = peso_x_unidad_input.value.replace(',', '.').strip().rstrip('-').rstrip('+')
                peso_u = float(peso_u_str or 0)
                peso_total_input.value = f"{cant * peso_u:.3f}"
                peso_total_input.update()
            except Exception as e:
                show_error("Error calculating total", e, "inventario_view.calcular_desde_unidades")
                peso_total_input.value = "0.000"
                peso_total_input.update()
        
        def calcular_desde_total(e):
            try:
                total_str = peso_total_input.value.replace(',', '.').strip().rstrip('-').rstrip('+')
                total = float(total_str or 0)
                cant = float(cant_x_unidad_input.value or 1)
                if cant > 0:
                    peso_x_unidad_input.value = f"{total / cant:.3f}"
                    peso_x_unidad_input.update()
            except Exception as e:
                show_error("Error calculating from total", e, "inventario_view.calcular_desde_total")
        
        cant_x_unidad_input = ft.TextField(
            label="Und.",
            value="1", 
            keyboard_type=ft.KeyboardType.NUMBER, 
            autofocus=True,
            border_radius=10,
            text_size=14,
            border_color=colors['input_border'],
            width=100,
            on_change=calcular_desde_unidades if es_pesable else None,
        )
        
        peso_x_unidad_input = ft.TextField(
            label="Kg/unidad",
            value="0.100", 
            keyboard_type=ft.KeyboardType.NUMBER, 
            border_radius=10,
            text_size=14,
            border_color=colors['input_border'],
            width=100,
            on_change=calcular_desde_unidades if es_pesable else None,
        )
        
        peso_total_input = ft.TextField(
            label="Peso Total",
            value="0.000", 
            keyboard_type=ft.KeyboardType.NUMBER, 
            border_radius=10,
            text_size=14,
            border_color=colors['input_border'],
            width=120,
            suffix_text="kg",
            focused_border_color=colors['accent'],
            on_change=calcular_desde_total if es_pesable else None,
        )
        
        cant_input_normal = ft.TextField(
            label="Cantidad",
            value="1", 
            keyboard_type=ft.KeyboardType.NUMBER, 
            autofocus=True,
            border_radius=10,
            text_size=16,
            border_color=colors['input_border'],
        )
        
        almacen_options = [ft.dropdown.Option(a, a.capitalize()) for a in almacenes_disponibles]
        almacen_dropdown = ft.Dropdown(
            label="Almacén",
            value=almacen_default,
            options=almacen_options,
            border_radius=10,
        )
        
        stock_texts = [ft.Text(f"{k.capitalize()}: {v:.0f}", size=12, color=colors['success']) for k, v in stock_por_almacen.items()]
        if not stock_texts:
            stock_texts = [ft.Text("Sin stock", size=12, color=colors['text_secondary'])]
        
        stock_info = ft.Container(
            content=ft.Column([
                ft.Text("📦 Stock por almacén:", size=12, weight="bold", color=colors['accent']),
                ft.Text(" • ".join([f"{k.title()}: {v:.0f}" for k, v in stock_por_almacen.items()]) if stock_por_almacen else "Sin stock", 
                       size=11, color=colors['text_secondary']),
            ], tight=True, spacing=2),
            bgcolor=colors['card_hover'],
            padding=12,
            border_radius=10,
        )

        def al_confirmar(e):
            if es_pesable:
                try:
                    cant_und = int(float(cant_x_unidad_input.value.replace(",", "").replace(" ", "")))
                    if cant_und <= 0: raise ValueError()
                except (ValueError, AttributeError):
                    cant_x_unidad_input.error_text = "Número mayor a 0"; cant_x_unidad_input.update(); return

                try:
                    peso_total = float(peso_total_input.value.replace(',', '.'))
                    if peso_total < 0: raise ValueError()
                except ValueError:
                    peso_total_input.error_text = "Peso válido mayor a 0"; peso_total_input.update(); return

                cantidad_a_guardar = 0
            else:
                try:
                    cantidad_a_guardar = int(float(cant_input_normal.value.replace(",", "").replace(" ", "")))
                    if cantidad_a_guardar <= 0: raise ValueError()
                except (ValueError, AttributeError):
                    cant_input_normal.error_text = "Número entero mayor a 0"; cant_input_normal.update(); return
                peso_total = 0.0

            almacen = almacen_dropdown.value or "principal"
            self._close_dialog()
            self._registrar_movimiento(tipo, cantidad_a_guardar, peso_total=peso_total, almacen=almacen)

        tipo_color = colors['success'] if tipo == "entrada" else colors['error']
        tipo_icon = "📥" if tipo == "entrada" else "📤"
        
        is_mobile = self.page.width < 600 if self.page else False
        
        if es_pesable:
            dialog_content = ft.Column([
                ft.Container(
                    content=ft.Text(producto.nombre, weight="bold", size=15, color=colors['text_primary']),
                    padding=5,
                    bgcolor=colors['card_hover'],
                    border_radius=8,
                    width=float('inf'),
                ),
                ft.Container(height=8),
                stock_info,
                ft.Container(height=8),
                ft.ResponsiveRow([
                    ft.Column([almacen_dropdown], col={"xs": 12, "sm": 6}),
                    ft.Column([cant_x_unidad_input], col={"xs": 12, "sm": 6}),
                ], spacing=10),
                ft.Container(height=5),
                ft.ResponsiveRow([
                    ft.Column([peso_x_unidad_input], col={"xs": 12, "sm": 6}),
                    ft.Column([peso_total_input], col={"xs": 12, "sm": 6}),
                ], spacing=10),
            ], tight=True, spacing=5)
        else:
            dialog_content = ft.Column([
                ft.Container(
                    content=ft.Text(producto.nombre, weight="bold", size=15, color=colors['text_primary']),
                    padding=5,
                    bgcolor=colors['card_hover'],
                    border_radius=8,
                    width=float('inf'),
                ),
                ft.Container(height=8),
                stock_info,
                ft.Container(height=8),
                ft.ResponsiveRow([
                    ft.Column([almacen_dropdown], col={"xs": 12, "sm": 6}),
                    ft.Column([cant_input_normal], col={"xs": 12, "sm": 6}),
                ], spacing=10),
            ], tight=True, spacing=5)
        
        dialog_width = max(400, int(self.page.width * 0.4)) if self.page else 400
        
        scrollable_content = ft.ListView(
            [dialog_content],
            auto_scroll=True,
        )
        
        content_container = ft.Container(
            content=scrollable_content,
            width=dialog_width,
            height=min(350, int(self.page.height * 0.45)) if self.page else 350,
        )
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Text(f"{tipo_icon} {tipo.capitalize()}", weight="bold", size=18, color=colors['text_primary']),
            content=content_container,
            actions=[
                ft.TextButton("Cancelar", on_click=self._close_dialog, style=ft.ButtonStyle(color=colors['text_secondary'])),
                ft.ElevatedButton(
                    "Confirmar", on_click=al_confirmar,
                    bgcolor=tipo_color, color="white"
                ),
            ],
            actions_alignment="space-between",
        )
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Text(f"{tipo_icon} {tipo.capitalize()}", weight="bold", size=18, color=colors['text_primary']),
            content=ft.Container(
                content=scrollable_content,
                width=dialog_width,
            ),
            actions=[
                ft.TextButton("Cancelar", on_click=self._close_dialog, style=ft.ButtonStyle(color=colors['text_secondary'])),
                ft.ElevatedButton(
                    "Confirmar", on_click=al_confirmar,
                    bgcolor=tipo_color, color="white"
                ),
            ],
            actions_alignment="space-between",
        )
        
        self.page.overlay.clear()
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _close_dialog(self, e=None):
        if self.active_dialog:
            self.active_dialog.open = False
            if self.page:
                self.page.update()
            self.active_dialog = None

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
                                    ft.Icons.DELETE_OUTLINE, 
                                    icon_color=ft.Colors.RED_400,
                                    icon_size=18,
                                    on_click=lambda _, index=i: self._eliminar_item_req(index, tabla),
                                ),
                            ], spacing=10),
                            padding=10,
                            bgcolor=ft.Colors.GREY_50,
                            border_radius=8,
                        )
                    )
            tabla.update()

    def _registrar_movimiento(self, tipo, cantidad, peso_total=0.0, almacen=None):
        from usr.database.local_replica import LocalReplica
        from usr.database.base import is_online, get_session_local
        from config.config import get_settings
        
        producto_id = self.producto_seleccionado.id if hasattr(self.producto_seleccionado, 'id') else self.producto_seleccionado.get('id')
        
        almacen_seleccionado = almacen or getattr(self.producto_seleccionado, 'almacen_predeterminado', 'principal') or 'principal'
        
        try:
            user_id = str(self.page.session.get("user_id")) if self.page else None
            if not user_id:
                user_id = "sistema"
        except Exception:
            user_id = "sistema"
        
        existencia_actual = LocalReplica.get_existencias_by_producto_almacen(producto_id, almacen_seleccionado)
        cant_anterior = existencia_actual.get('cantidad', 0) if existencia_actual else 0
        
        es_pesable = _get_attr(self.producto_seleccionado, 'es_pesable', False)
        
        if es_pesable and peso_total > 0:
            cantidad_a_mover = peso_total
            unidad = 'kg'
        else:
            cantidad_a_mover = cantidad
            unidad = _get_attr(self.producto_seleccionado, 'unidad_medida', 'unidad')
        
        if tipo == "entrada":
            cant_nueva = cant_anterior + cantidad_a_mover
        else:
            if cant_anterior < cantidad_a_mover:
                show_error_notif("Stock insuficiente"); return
            cant_nueva = cant_anterior - cantidad_a_mover
        
        movimiento_data = {
            "producto_id": producto_id,
            "tipo": tipo,
            "cantidad": cantidad,
            "cantidad_anterior": cant_anterior,
            "cantidad_nueva": cant_nueva,
            "peso_total": peso_total,
            "almacen": almacen_seleccionado,
            "registrado_por": user_id,
            "observaciones": "",
            "fecha_movimiento": datetime.now().isoformat(),
        }
        
        LocalReplica.save_movimiento(movimiento_data, skip_sync=True)
        LocalReplica.update_existencia(producto_id, almacen_seleccionado, cant_nueva, unidad)
        
        local_id = movimiento_data.get('id')
        
        sync_mgr = None
        try:
            from usr.database import get_sync_manager
            sync_mgr = get_sync_manager()
        except Exception as e:
            show_error("Error getting sync manager", e, "inventario_view")
        
        online = is_online() if sync_mgr is None else sync_mgr.check_connection()
        
        if online:
            try:
                from sqlalchemy import create_engine, text
                from config.config import get_settings
                settings = get_settings()
                remote_engine = create_engine(settings.DATABASE_URL)
                
                with remote_engine.connect() as conn:
                    mov_clean = {k: v for k, v in movimiento_data.items() 
                               if k not in ('sincronizado', 'created_at')}
                    mov_clean.pop('id', None)
                    
                    cols = ", ".join(mov_clean.keys())
                    vals = ", ".join([f":{k}" for k in mov_clean.keys()])
                    sql = text(f"INSERT INTO movimientos ({cols}) VALUES ({vals})")
                    conn.execute(sql, mov_clean)
                    conn.commit()
                    
                    exist_sql = text("""
                        INSERT INTO existencias (producto_id, almacen, cantidad, unidad)
                        VALUES (:producto_id, :almacen, :cantidad, :unidad)
                        ON CONFLICT (producto_id, almacen) 
                        DO UPDATE SET cantidad = :cantidad, unidad = :unidad
                    """)
                    conn.execute(exist_sql, {
                        'producto_id': producto_id,
                        'almacen': almacen_seleccionado,
                        'cantidad': cant_nueva,
                        'unidad': unidad
                    })
                    conn.commit()
                
                remote_engine.dispose()
                
                if local_id:
                    LocalReplica.mark_movimiento_sincronizado(local_id)
                    
                print("[SYNC] Movimiento syncado inmediatamente")
                sync_exito = True
            except Exception as e:
                show_error("Error syncing movement", e, "inventario_view._add_movimiento")
                print(f"[SYNC] Error al syncar: {e}")
                sync_exito = False
        else:
            sync_exito = False
        
        if not sync_exito:
            try:
                from usr.database.sync_queue import get_sync_queue
                queue = get_sync_queue()
                queue.add_pending('movimientos', 'insert', movimiento_data)
            except Exception as e:
                show_error("Error adding to sync queue", e, "inventario_view._add_movimiento")
        
        show_success(f"{tipo.capitalize()} registrada: {cantidad}")
        self._load_productos()