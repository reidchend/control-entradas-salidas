import flet as ft
import asyncio
from datetime import datetime
from app.database.base import get_db
from app.models import Categoria, Producto, Movimiento
from app.logger import get_logger
import traceback

logger = get_logger(__name__)

class InventarioView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True 
        self.padding = ft.padding.only(left=10, right=10, bottom=16, top=8)
        self.bgcolor = ft.Colors.GREY_50

        # Componentes UI inicializados en None
        self.search_field = None
        self.productos_list = None
        self.active_dialog = None
        
        # Grid de categorías: 3 columnas y Scroll automático
        self.categorias_grid = ft.GridView(
            expand=True,
            runs_count=3,           
            max_extent=120,         
            child_aspect_ratio=0.8, 
            spacing=10,
            run_spacing=10,
        )

        self.main_content_area = ft.AnimatedSwitcher(
            content=self.categorias_grid,
            transition=ft.AnimatedSwitcherTransition.FADE,
            duration=300,
            expand=True, 
        )

        self.categoria_seleccionada = None
        self.producto_seleccionado = None
        self._is_initialized = False
        self._categorias_cache = None

        self._build_ui()

    def did_mount(self):
        """Se ejecuta cuando el control se añade a la página."""
        if not self._is_initialized:
            # Usamos run_task para que la carga de datos no bloquee el renderizado inicial
            if self.page:
                self.page.run_task(self._load_categorias)
            self._is_initialized = True

    def _build_ui(self):
        try:
            self.header_container = ft.Container(
                content=ft.Row([
                    ft.Column([
                        ft.Text("Inventario", size=22, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_GREY_900),
                        ft.Text("Gestión de existencias", size=12, color=ft.Colors.BLUE_GREY_400),
                    ], expand=True, spacing=0),
                    ft.IconButton(
                        icon=ft.Icons.REFRESH_ROUNDED,
                        on_click=lambda _: self.page.run_task(self._load_categorias, True),
                    )
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                margin=ft.margin.only(bottom=10)
            )

            self.search_field = ft.TextField(
                hint_text="Buscar...",
                prefix_icon=ft.Icons.SEARCH_ROUNDED,
                border_radius=12,
                bgcolor=ft.Colors.WHITE,
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

    async def _load_categorias(self, force_refresh=False):
        db = None
        try:
            db = next(get_db())
            categorias = db.query(Categoria).all()
            self._categorias_cache = categorias
            
            if not categorias:
                self.categorias_grid.controls = [ft.Text("No hay categorías")]
            else:
                self.categorias_grid.controls = [self._create_categoria_card(c) for c in categorias]
            
            # Solo actualizamos si el componente está montado en la página
            if self.page:
                self.update()
        except Exception as e:
            logger.error(f"Error carga: {e}")
        finally:
            if db: db.close()

    async def _handle_category_click(self, container, categoria):
        """Maneja la animación y el cambio de vista."""
        try:
            container.scale = 0.90
            container.update()
            await asyncio.sleep(0.1)
            container.scale = 1.0
            container.update()
            self._show_productos(categoria)
        except Exception as e:
            logger.error(f"Error en clic categoría: {e}")

    def _create_categoria_card(self, categoria):
        cat_color = categoria.color if categoria.color else ft.Colors.BLUE_900
        
        card = ft.Container(
            bgcolor=ft.Colors.WHITE,
            border_radius=12,
            padding=8,
            animate_scale=150,
            border=ft.border.all(1, ft.Colors.with_opacity(0.1, cat_color)),
            content=ft.Column([
                ft.Icon(ft.Icons.CATEGORY_ROUNDED, size=28, color=cat_color),
                ft.Text(
                    str(categoria.nombre).upper(), 
                    weight="bold", 
                    size=10, 
                    text_align="center", 
                    color=cat_color,
                    max_lines=2,
                    overflow=ft.TextOverflow.ELLIPSIS
                ),
            ], alignment="center", horizontal_alignment="center", spacing=2)
        )

        # Capturamos el evento 'e' para que no se confunda con 'container'
        card.on_click = lambda e: self.page.run_task(self._handle_category_click, card, categoria)
        return card

    def _show_productos(self, categoria):
        self.categoria_seleccionada = categoria
        header_nav = ft.Row([
            ft.IconButton(ft.Icons.ARROW_BACK_ROUNDED, on_click=lambda _: self._reset_view()),
            ft.Text(categoria.nombre, size=18, weight="bold", color=categoria.color),
        ])
        
        self.productos_list = ft.ListView(expand=True, spacing=10, padding=ft.padding.only(top=10))
        
        nueva_vista = ft.Column([header_nav, self.productos_list], expand=True)
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
            db = next(get_db())
            query = db.query(Producto).filter(Producto.categoria_id == self.categoria_seleccionada.id)
            if search_term:
                query = query.filter(Producto.nombre.ilike(f"%{search_term}%"))
            productos = query.all()
            
            items = [self._create_producto_item(p) for p in productos if p]
            self.productos_list.controls = items if items else [ft.Text("No hay productos")]
            if self.page: self.update()
        except Exception as e:
            logger.error(f"Error carga productos: {e}")
        finally:
            if db: db.close()

    def _create_producto_item(self, producto):
        stock = producto.stock_actual or 0
        stock_min = producto.stock_minimo or 0
        stock_color = ft.Colors.RED_600 if stock < stock_min else ft.Colors.PRIMARY
        
        es_pesable = getattr(producto, 'es_pesable', False)
        badge_pesable = ft.Container(
            content=ft.Text("PESABLE", size=9, color=ft.Colors.WHITE, weight="bold"),
            bgcolor=ft.Colors.ORANGE_700,
            padding=ft.padding.symmetric(horizontal=4, vertical=1),
            border_radius=3
        ) if es_pesable else ft.Container()

        return ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Row([ft.Text(str(producto.nombre), weight="bold", size=14), badge_pesable], spacing=5),
                    ft.Row([
                        ft.Container(
                            content=ft.Text(f"Stock: {stock}", size=10, weight="bold", color=ft.Colors.WHITE),
                            bgcolor=stock_color, padding=ft.padding.symmetric(horizontal=6, vertical=2), border_radius=5
                        ),
                        ft.Text(f"Mín: {stock_min}", size=10, color=ft.Colors.GREY_500),
                    ], spacing=10)
                ], expand=True),
                ft.IconButton(ft.Icons.ADD_CIRCLE_OUTLINE_ROUNDED, icon_color="green", icon_size=24,
                             on_click=lambda _, p=producto: self._show_cantidad_dialog(p, "entrada")),
                ft.IconButton(ft.Icons.REMOVE_CIRCLE_OUTLINE_ROUNDED, icon_color="red", icon_size=24,
                             on_click=lambda _, p=producto: self._show_cantidad_dialog(p, "salida")),
            ], spacing=5),
            padding=10, bgcolor=ft.Colors.WHITE, border_radius=10, border=ft.border.all(1, "#eeeeee")
        )

    def _show_cantidad_dialog(self, producto, tipo):
        self.producto_seleccionado = producto
        es_pesable = getattr(producto, 'es_pesable', False)
        
        cant_input = ft.TextField(label="Unidades/Bultos", value="1", keyboard_type=ft.KeyboardType.NUMBER, autofocus=True, suffix_text="uds")
        peso_input = ft.TextField(label="Peso Total (Kg)", hint_text="0.00", keyboard_type=ft.KeyboardType.NUMBER, visible=es_pesable, suffix_text="kg")

        def al_confirmar(e):
            try:
                cantidad = int(cant_input.value)
                if cantidad <= 0: raise ValueError()
            except ValueError:
                cant_input.error_text = "Número entero mayor a 0"; cant_input.update(); return

            peso_valor = 0.0
            if es_pesable:
                try:
                    peso_valor = float(peso_input.value.replace(',', '.'))
                    if peso_valor <= 0: raise ValueError()
                except ValueError:
                    peso_input.error_text = "Ingrese un peso válido"; peso_input.update(); return

            self._close_dialog()
            self._registrar_movimiento(tipo, cantidad, peso_total=peso_valor)

        self.active_dialog = ft.AlertDialog(
            title=ft.Text(f"Registrar {tipo.capitalize()}"),
            content=ft.Column([ft.Text(f"Producto: {producto.nombre}", weight="bold"), cant_input, peso_input], tight=True, spacing=15),
            actions=[ft.TextButton("Cancelar", on_click=self._close_dialog), ft.ElevatedButton("Confirmar", on_click=al_confirmar)]
        )
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        if self.page: self.page.update()

    def _registrar_movimiento(self, tipo, cantidad, peso_total=0.0):
        db = None
        try:
            db = next(get_db())
            prod = db.query(Producto).filter(Producto.id == self.producto_seleccionado.id).first()
            user_id = self.page.session.get("user_id") or 1
            cant_anterior = prod.stock_actual or 0
            
            if tipo == "entrada":
                cant_nueva = cant_anterior + cantidad
            else:
                if cant_anterior < cantidad:
                    self._show_error("Stock insuficiente"); return
                cant_nueva = cant_anterior - cantidad

            nuevo_mov = Movimiento(
                producto_id=prod.id, tipo=tipo, cantidad=cantidad,
                cantidad_anterior=cant_anterior, cantidad_nueva=cant_nueva,
                registrado_por=user_id, fecha_movimiento=datetime.now(), peso_total=peso_total
            )
            prod.stock_actual = cant_nueva
            db.add(nuevo_mov)
            db.commit()
            
            self._show_message(f"✓ {tipo.capitalize()} registrada")
            self._load_productos(search_term=self.search_field.value)
        except Exception as e:
            if db: db.rollback()
            self._show_error(f"Error: {e}")
        finally:
            if db: db.close()

    def _on_search_change(self, e):
        term = e.control.value.lower()
        if self.categoria_seleccionada:
            self._load_productos(term)
        elif self._categorias_cache:
            filtered = [c for c in self._categorias_cache if term in c.nombre.lower()]
            self.categorias_grid.controls = [self._create_categoria_card(c) for c in filtered]
            self.categorias_grid.update()

    def _close_dialog(self, e=None):
        if self.active_dialog:
            self.active_dialog.open = False
            if self.page: self.page.update()

    def _show_message(self, texto):
        snack = ft.SnackBar(content=ft.Text(texto), bgcolor=ft.Colors.GREEN_700)
        self.page.overlay.append(snack)
        snack.open = True
        if self.page: self.page.update()

    def _show_error(self, texto):
        snack = ft.SnackBar(content=ft.Text(texto), bgcolor=ft.Colors.RED_700)
        self.page.overlay.append(snack)
        snack.open = True
        if self.page: self.page.update()