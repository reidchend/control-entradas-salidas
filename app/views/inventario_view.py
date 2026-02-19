import flet as ft
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
        self.padding = ft.padding.only(left=16, right=16, bottom=16, top=8)
        self.bgcolor = ft.Colors.GREY_50

        # Componentes UI
        self.categorias_grid = None
        self.search_field = None
        self.productos_list = None
        self.active_dialog = None
        
        # Estado
        self.categoria_seleccionada = None
        self.producto_seleccionado = None
        self._is_initialized = False
        
        # Cache
        self._categorias_cache = None

        self._build_ui()

    def did_mount(self):
        # Evitar doble carga si el componente se monta varias veces
        if not self._is_initialized:
            logger.info("InventarioView montada")
            self._load_categorias()
            self._is_initialized = True

    def _build_ui(self):
        try:
            self.header_container = ft.Container(
                content=ft.Row([
                    ft.Column([
                        ft.Text("Inventario", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_GREY_900),
                        ft.Text("Gestión de existencias y auditoría", size=14, color=ft.Colors.BLUE_GREY_400),
                    ], expand=True, spacing=0),
                    ft.IconButton(
                        icon=ft.Icons.REFRESH_ROUNDED,
                        icon_color=ft.Colors.PRIMARY,
                        on_click=lambda _: self._load_categorias(force_refresh=True),
                        tooltip="Actualizar categorías"
                    )
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                margin=ft.margin.only(bottom=15)
            )

            self.search_field = ft.TextField(
                hint_text="Buscar producto...",
                prefix_icon=ft.Icons.SEARCH_ROUNDED,
                border_radius=12,
                bgcolor=ft.Colors.WHITE,
                border_color=ft.Colors.GREY_300,
                focused_border_color=ft.Colors.PRIMARY,
                height=48,
                text_size=14,
                on_change=self._on_search_change,
            )

            self.categorias_grid = ft.GridView(
                expand=True,
                runs_count=2,
                max_extent=200,
                child_aspect_ratio=1.0,
                spacing=15,
                run_spacing=15,
            )

            self.content = ft.Column([
                self.header_container,
                self.search_field,
                ft.Container(height=10),
                ft.Text("Seleccionar Categoría", size=16, weight=ft.FontWeight.W_600, color=ft.Colors.BLUE_GREY_800),
                self.categorias_grid,
            ], spacing=0, expand=True)
            
        except Exception as e:
            logger.error(f"Error al construir la interfaz: {e}", exc_info=True)
            self._show_error("Error al construir la interfaz")

    def _load_categorias(self, force_refresh=False):
        db = None
        self.categorias_grid.controls = [ft.ProgressRing()]
        self.update()
        try:
            db = next(get_db())
            categorias = db.query(Categoria).all()
            if not categorias:
                self.categorias_grid.controls = [ft.Text("No hay categorías configuradas")]
            else:
                cards = []
                for c in categorias:
                    card = self._create_categoria_card(c)
                    if card: cards.append(card)
                self.categorias_grid.controls = cards
                self._categorias_cache = categorias
            if self.page: self.page.update()
        except Exception as e:
            logger.error(f"Error al cargar categorías: {e}")
            self._show_error(f"Error al cargar categorías")
        finally:
            if db: db.close()

    def _create_categoria_card(self, categoria):
        return ft.Container(
            content=ft.Column([
                ft.Icon(ft.Icons.CATEGORY_ROUNDED, size=40, color=ft.Colors.PRIMARY),
                ft.Text(str(categoria.nombre).upper(), weight="bold", size=13, text_align="center"),
                ft.Text("Ver productos", size=10, color=ft.Colors.GREY_500),
            ], alignment="center", horizontal_alignment="center", spacing=5),
            bgcolor=ft.Colors.WHITE,
            border_radius=15,
            padding=15,
            on_click=lambda _, c=categoria: self._show_productos(c),
            border=ft.border.all(1, ft.Colors.GREY_200)
        )

    def _show_productos(self, categoria):
        self.categoria_seleccionada = categoria
        header_nav = ft.Row([
            ft.IconButton(ft.Icons.ARROW_BACK_ROUNDED, on_click=lambda _: self._reset_view()),
            ft.Text(categoria.nombre, size=20, weight="bold"),
        ])
        self.productos_list = ft.ListView(expand=True, spacing=10, padding=ft.padding.only(top=10))
        self.content.controls = [header_nav, self.search_field, self.productos_list]
        self._load_productos()
        if self.page: self.page.update()

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
            if self.page: self.page.update()
        except Exception as e:
            logger.error(f"Error al cargar productos: {e}")
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
                    ft.Row([ft.Text(str(producto.nombre), weight="bold", size=15), badge_pesable], spacing=5),
                    ft.Row([
                        ft.Container(
                            content=ft.Text(f"Stock: {stock}", size=11, weight="bold", color=ft.Colors.WHITE),
                            bgcolor=stock_color, padding=ft.padding.symmetric(horizontal=8, vertical=2), border_radius=5
                        ),
                        ft.Text(f"Mín: {stock_min}", size=11, color=ft.Colors.GREY_500),
                    ], spacing=10)
                ], expand=True),
                ft.IconButton(
                    icon=ft.Icons.ADD_CIRCLE_OUTLINE_ROUNDED, 
                    icon_color=ft.Colors.GREEN_600, 
                    on_click=lambda _, p=producto: self._show_cantidad_dialog(p, "entrada")
                ),
                ft.IconButton(
                    icon=ft.Icons.REMOVE_CIRCLE_OUTLINE_ROUNDED, 
                    icon_color=ft.Colors.RED_600, 
                    on_click=lambda _, p=producto: self._show_cantidad_dialog(p, "salida")
                ),
            ], spacing=10),
            padding=12, bgcolor=ft.Colors.WHITE, border_radius=12, border=ft.border.all(1, ft.Colors.GREY_200)
        )

    def _show_cantidad_dialog(self, producto, tipo):
        self.producto_seleccionado = producto
        es_pesable = getattr(producto, 'es_pesable', False)
        
        cant_input = ft.TextField(
            label="Unidades/Bultos", 
            value="1", 
            keyboard_type=ft.KeyboardType.NUMBER,
            autofocus=True,
            suffix_text="uds"
        )
        
        peso_input = ft.TextField(
            label="Peso Total (Kg)",
            hint_text="0.00",
            keyboard_type=ft.KeyboardType.NUMBER,
            visible=es_pesable,
            suffix_text="kg"
        )

        def al_confirmar(e):
            try:
                cantidad = int(cant_input.value)
                if cantidad <= 0: raise ValueError()
            except ValueError:
                cant_input.error_text = "Número entero mayor a 0"
                cant_input.update()
                return

            peso_valor = 0.0
            if es_pesable:
                try:
                    peso_valor = float(peso_input.value.replace(',', '.'))
                    if peso_valor <= 0: raise ValueError()
                except ValueError:
                    peso_input.error_text = "Ingrese un peso válido"
                    peso_input.update()
                    return

            self._close_dialog()
            self._registrar_movimiento(tipo, cantidad, peso_total=peso_valor)

        dialog_content = ft.Column([
            ft.Text(f"Producto: {producto.nombre}", weight="bold"),
            cant_input,
            peso_input,
        ], tight=True, spacing=15)

        self.active_dialog = ft.AlertDialog(
            title=ft.Text(f"Registrar {tipo.capitalize()}"),
            content=dialog_content,
            actions=[
                ft.TextButton("Cancelar", on_click=self._close_dialog),
                ft.ElevatedButton("Confirmar", on_click=al_confirmar)
            ]
        )

        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _registrar_movimiento(self, tipo, cantidad, peso_total=0.0):
        db = None
        try:
            db = next(get_db())
            prod = db.query(Producto).filter(Producto.id == self.producto_seleccionado.id).first()
            
            if not prod:
                self._show_error("Producto no encontrado")
                return

            user_id = self.page.session.get("user_id") or 1
            cant_anterior = prod.stock_actual or 0
            
            if tipo == "entrada":
                cant_nueva = cant_anterior + cantidad
            else:
                if cant_anterior < cantidad:
                    self._show_error("Stock insuficiente")
                    return
                cant_nueva = cant_anterior - cantidad

            # Corregido: Se eliminó el argumento 'nota' que no existe en el modelo Movimiento
            nuevo_mov = Movimiento(
                producto_id=prod.id,
                tipo=tipo,
                cantidad=cantidad,
                cantidad_anterior=cant_anterior,
                cantidad_nueva=cant_nueva,
                registrado_por=user_id,
                fecha_movimiento=datetime.now(),
                peso_total=peso_total
            )
            
            prod.stock_actual = cant_nueva
            db.add(nuevo_mov)
            db.commit()
            
            msg = f"✓ {tipo.capitalize()} registrada"
            if peso_total > 0: msg += f" ({peso_total}kg)"
            self._show_message(msg)
            self._load_productos(search_term=self.search_field.value)
            
        except Exception as e:
            if db: db.rollback()
            logger.error(f"Error al guardar movimiento: {e}")
            self._show_error(f"Error al guardar: {str(e)[:50]}")
        finally:
            if db: db.close()

    def _reset_view(self):
        self.categoria_seleccionada = None
        self._build_ui()
        self._load_categorias()
        if self.page: self.page.update()

    def _on_search_change(self, e):
        if self.categoria_seleccionada:
            self._load_productos(e.control.value)

    def _close_dialog(self, e=None):
        if self.active_dialog:
            self.active_dialog.open = False
            self.page.update()

    def _show_message(self, texto):
        snack = ft.SnackBar(content=ft.Text(texto), bgcolor=ft.Colors.GREEN_700)
        if self.page:
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()

    def _show_error(self, texto):
        snack = ft.SnackBar(content=ft.Text(texto), bgcolor=ft.Colors.RED_700)
        if self.page:
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()