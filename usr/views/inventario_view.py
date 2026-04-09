import flet as ft
import asyncio
import hashlib
from datetime import datetime
from usr.database.base import get_db
from usr.models import Categoria, Producto, Movimiento, Existencia
from usr.logger import get_logger
from usr.theme import get_theme
from sqlalchemy import func
import traceback


def _generar_color(texto):
    hash_hcl = hashlib.md5(texto.encode()).hexdigest()
    return f"#{hash_hcl[:6]}"


def _colors(page):
    if page and hasattr(page, 'theme_mode'):
        return get_theme(page.theme_mode == ft.ThemeMode.DARK)
    return get_theme(True)

try:
    from usr.database.cache import get_cache, set_cache, get_cache_any_age
    CACHE_AVAILABLE = True
except ImportError:
    CACHE_AVAILABLE = False

logger = get_logger(__name__)

class InventarioView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True 
        self.padding = ft.padding.only(left=10, right=10, bottom=16, top=8)
        self.bgcolor = '#1A1A1A'

        # Componentes UI inicializados en None
        self.search_field = None
        self.productos_list = None
        self.active_dialog = None
        
        # Grid de categorías: Scroll automático
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

        self._build_ui()

    def on_theme_change(self):
        """Se llama cuando cambia el tema"""
        if not self.page:
            return
            
        colors = _colors(self.page)
        self.bgcolor = colors['bg']
        
        if hasattr(self, 'main_content_area'):
            self.main_content_area.bgcolor = colors['surface']
        
        if hasattr(self, 'search_field'):
            self.search_field.border_color = colors['input_border']
            self.search_field.focused_border_color = colors['accent']
        
        if hasattr(self, 'header_container'):
            self._build_ui()
        
        if hasattr(self, 'categorias_grid'):
            self.page.run_task(self._load_categorias, True)

    def did_mount(self):
        """Se ejecuta cuando el control se añade a la página."""
        if not self._is_initialized:
            # Usamos run_task para que la carga de datos no bloquee el renderizado inicial
            if self.page:
                self.page.run_task(self._load_categorias)
            self._is_initialized = True

    def _build_ui(self):
        try:
            colors = _colors(self.page)
            self.header_container = ft.Container(
                content=ft.Row([
                    ft.Column([
                        ft.Text("Inventario", size=22, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                        ft.Text("Gestión de existencias", size=12, color=colors['text_secondary']),
                    ], expand=True, spacing=0),
                    ft.ElevatedButton(
                        content=ft.Row([
                            ft.Icon(ft.Icons.ASSIGNMENT, size=18),
                            ft.Text("Requisición"),
                        ], spacing=5),
                        on_click=lambda _: self._show_panel_requisicion(),
                        bgcolor='#FF9800',
                        color="white",
                    ),
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
            logger.error(f"Error UI: {e}")

    def _on_refresh(self):
        """Refresca datos desde la BD directamente"""
        self.page.run_task(self._load_categorias, True)
        
        if self.categoria_seleccionada:
            self._load_productos()
        elif self._vista_requisicion_activa:
            pass
        
        if self.page:
            snack = ft.SnackBar(
                content=ft.Text("🔄 Actualizando..."),
                bgcolor=ft.Colors.BLUE_600,
                duration=1,
            )
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()

    async def _load_categorias(self, force_refresh=False):
        db = None
        try:
            # 1. Intentar cargar del caché primero (rápido)
            if CACHE_AVAILABLE and not force_refresh:
                cached_cats = get_cache_any_age("categorias")
                if cached_cats:
                    self.categorias_grid.controls = [
                        self._create_categoria_card_from_dict(c) for c in cached_cats
                    ]
                    if self.page:
                        self.update()

            # 2. Cargar de la BD (puede ser lento)
            db = next(get_db())
            categorias = db.query(Categoria).all()
            self._categorias_cache = categorias
            
            # 3. Guardar en caché
            if CACHE_AVAILABLE:
                cats_data = [
                    {"id": c.id, "nombre": c.nombre, "color": c.color}
                    for c in categorias
                ]
                set_cache("categorias", cats_data, ttl_seconds=86400)
            
            if not categorias:
                self.categorias_grid.controls = [ft.Text("No hay categorías")]
            else:
                self.categorias_grid.controls = [self._create_categoria_card(c) for c in categorias]
            
            if self.page:
                self.update()
                if force_refresh:
                    snack = ft.SnackBar(
                        content=ft.Text("✓ Datos actualizados desde BD"),
                        bgcolor=ft.Colors.GREEN_700,
                        duration=2,
                    )
                    self.page.overlay.append(snack)
                    snack.open = True
                    self.page.update()
        except Exception as e:
            logger.error(f"Error carga: {e}")
        finally:
            if db: db.close()

    def _on_search_change(self, e=None):
        """Filtra categorías según el término de búsqueda"""
        search_term = self.search_field.value.lower().strip() if self.search_field and self.search_field.value else ""
        if self._categorias_cache:
            if search_term:
                filtered = [c for c in self._categorias_cache if search_term in c.get("nombre", "").lower()]
            else:
                filtered = self._categorias_cache
            self.categorias_grid.controls = [self._create_categoria_card_from_dict(c) for c in filtered]
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
            logger.error(f"Error en clic categoría: {e}")

    def _get_card_bg(self):
        """Retorna el color de fondo según el tema"""
        if self.page and self.page.theme_mode == ft.ThemeMode.LIGHT:
            return '#F0F4F8'
        return '#2D2D2D'

    def _create_categoria_card(self, categoria):
        cat_color = categoria.color if categoria.color else _generar_color(categoria.nombre)
        inicial = categoria.nombre[0].upper() if categoria.nombre else "?"
        
        colors = _colors(self.page)
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
            animate=ft.Animation(350, ft.AnimationCurve.DECELERATE),
            animate_scale=ft.Animation(300, ft.AnimationCurve.EASE_OUT),
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
                        str(categoria.nombre).upper(),
                        size=10,
                        weight="bold",
                        color=text_color,
                        text_align=ft.TextAlign.CENTER,
                        max_lines=2,
                        overflow=ft.TextOverflow.ELLIPSIS
                    ),
                    ft.Text("Ver más", size=9, color=text_secondary)
                ]
            )
        )
        card.on_hover = lambda e: self._al_pasar_mouse(e, card, cat_color)
        card.on_click = lambda e: self.page.run_task(self._handle_category_click, card, categoria)
        return card

    def _al_pasar_mouse(self, e, card, cat_color):
        if e.data == "true":
            card.scale = 1.05
            card.border = ft.border.all(2, cat_color)
            card.shadow = ft.BoxShadow(
                blur_radius=25,
                color=ft.Colors.with_opacity(0.3, cat_color),
                offset=ft.Offset(0, 10)
            )
        else:
            card.scale = 1.0
            card.border = ft.border.only(bottom=ft.BorderSide(3, cat_color))
            card.shadow = None
        card.update()

    def _create_categoria_card_from_dict(self, cat_dict):
        """Crea tarjeta de categoría desde diccionario (caché)"""
        nombre = cat_dict.get("nombre", "")
        cat_color = cat_dict.get("color") or _generar_color(nombre)
        inicial = nombre[0].upper() if nombre else "?"
        
        colors = _colors(self.page)
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
            animate=ft.Animation(350, ft.AnimationCurve.DECELERATE),
            animate_scale=ft.Animation(300, ft.AnimationCurve.EASE_OUT),
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
                    ft.Text("Ver más", size=9, color=text_secondary)
                ]
            )
        )
        card.on_hover = lambda e: self._al_pasar_mouse(e, card, cat_color)
        cat_obj = type('Categoria', (), cat_dict)()
        card.on_click = lambda e: self.page.run_task(self._handle_category_click, card, cat_obj)
        return card

    def _show_productos(self, categoria):
        self.categoria_seleccionada = categoria
        colors = _colors(self.page)
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
        
        nueva_vista = ft.Column([header_nav, self.productos_list], expand=True, spacing=5)
        self.main_content_area.content = nueva_vista
        self._load_productos()
        if self.page: self.update()

    def _reset_view(self):
        self.categoria_seleccionada = None
        self.search_field.value = ""
        self.main_content_area.content = self.categorias_grid
        # Refrescamos el grid para asegurar el estado limpio
        if self._categorias_cache:
            self.categorias_grid.controls = [self._create_categoria_card(c) for c in self._categorias_cache]
        if self.page: self.update()

    def _load_productos(self, search_term=""):
        if not self.categoria_seleccionada: return
        db = None
        try:
            cat_id = self.categoria_seleccionada.id
            
            # 1. Intentar cargar del caché primero
            if CACHE_AVAILABLE:
                cached_prods = get_cache_any_age(f"productos_cat_{cat_id}")
                cached_exist = get_cache_any_age(f"existencias_cat_{cat_id}")
                
                if cached_prods:
                    existencias_map = cached_exist or {}
                    if search_term:
                        cached_prods = [p for p in cached_prods if search_term.lower() in p.get("nombre", "").lower()]
                    
                    items = [self._create_producto_item_from_dict(p, existencias_map.get(str(p.get("id")), {})) for p in cached_prods]
                    self.productos_list.controls = items if items else [ft.Text("No hay productos")]
                    if self.page: self.update()
            
            # 2. Cargar de la BD
            db = next(get_db())
            
            productos = db.query(Producto).filter(Producto.categoria_id == cat_id).all()
            producto_ids = [p.id for p in productos]
            
            existencias_map = {}
            if producto_ids:
                existencias = db.query(Existencia.producto_id, Existencia.almacen, Existencia.cantidad).filter(
                    Existencia.producto_id.in_(producto_ids)
                ).all()
                for e in existencias:
                    if e.producto_id not in existencias_map:
                        existencias_map[e.producto_id] = {}
                    existencias_map[e.producto_id][e.almacen] = e.cantidad
            
            # 3. Guardar en caché
            if CACHE_AVAILABLE and productos:
                prods_data = [
                    {"id": p.id, "nombre": p.nombre, "unidad_medida": p.unidad_medida, "stock_minimo": p.stock_minimo}
                    for p in productos
                ]
                set_cache(f"productos_cat_{cat_id}", prods_data, ttl_seconds=86400)
                set_cache(f"existencias_cat_{cat_id}", existencias_map, ttl_seconds=3600)
            
            if search_term:
                productos = [p for p in productos if search_term.lower() in p.nombre.lower()]
            
            items = [self._create_producto_item(p, existencias_map.get(p.id, {})) for p in productos if p]
            self.productos_list.controls = items if items else [ft.Text("No hay productos")]
            if self.page: self.update()
        except Exception as e:
            logger.error(f"Error carga productos: {e}")
        finally:
            if db: db.close()

    def _create_producto_item(self, producto, stock_por_almacen=None):
        if stock_por_almacen is None:
            stock_por_almacen = {}
        colors = _colors(self.page)
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
        colors = _colors(self.page)
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
        db = next(get_db())
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
        es_pesable = getattr(producto, 'es_pesable', False)
        
        almacen_default = producto.almacen_predeterminado or "principal"
        
        db = next(get_db())
        try:
            existencias = db.query(Existencia).filter(Existencia.producto_id == producto.id).all()
            stock_por_almacen = {e.almacen: e.cantidad for e in existencias}
            todos_almacenes = db.query(Existencia.almacen).distinct().all()
            almacenes_disponibles = [a[0] for a in todos_almacenes]
            if "principal" not in almacenes_disponibles:
                almacenes_disponibles.append("principal")
        finally:
            db.close()
        
        colors = _colors(self.page)
        cant_input = ft.TextField(
            label="Cantidad (Bultos/Unidades)",
            value="1", 
            keyboard_type=ft.KeyboardType.NUMBER, 
            autofocus=True,
            border_radius=10,
            text_size=16,
            border_color=colors['input_border'],
        )
        
        peso_input = ft.TextField(
            label="Peso Total (Kg)", 
            hint_text="0.000", 
            keyboard_type=ft.KeyboardType.NUMBER, 
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
            try:
                valor = cant_input.value.replace(",", "").replace(" ", "")
                cantidad = int(float(valor))
                if cantidad <= 0: raise ValueError()
            except (ValueError, AttributeError):
                cant_input.error_text = "Número entero mayor a 0"; cant_input.update(); return

            peso_valor = 0.0
            if es_pesable:
                try:
                    peso_valor = float(peso_input.value.replace(',', '.'))
                    if peso_valor <= 0: raise ValueError()
                except ValueError:
                    peso_input.error_text = "Ingrese un peso válido"; peso_input.update(); return

            almacen = almacen_dropdown.value or "principal"
            self._close_dialog()
            self._registrar_movimiento(tipo, cantidad, peso_total=peso_valor, almacen=almacen)

        tipo_color = colors['success'] if tipo == "entrada" else colors['error']
        tipo_icon = "📥" if tipo == "entrada" else "📤"
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Text(f"{tipo_icon} Registrar {tipo.capitalize()}", weight="bold", size=18, color=colors['text_primary']),
            content=ft.Container(
                content=ft.Column([
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
                        ft.Column([almacen_dropdown], col={"xs": 12, "md": 6}),
                        ft.Column([cant_input], col={"xs": 12, "md": 6}),
                    ], spacing=10),
                    ft.Container(height=5),
                    peso_input if es_pesable else ft.Container(),
                ], tight=True, spacing=5),
                width=350,
            ),
            actions=[
                ft.TextButton("Cancelar", on_click=self._close_dialog, style=ft.ButtonStyle(color=colors['text_secondary'])),
                ft.ElevatedButton(
                    "Confirmar", on_click=al_confirmar,
                    bgcolor=tipo_color, color="white"
                ),
            ],
            actions_alignment="end",
        )
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

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