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
        
        # Estado
        self.categoria_seleccionada = None
        self.producto_seleccionado = None
        
        # Cache
        self._categorias_cache = None

        self._build_ui()

    def did_mount(self):
        """Se ejecuta cuando el componente se monta en la página."""
        logger.info("InventarioView montada")
        self._load_categorias()

    def _build_ui(self):
        """Construye la interfaz de usuario inicial."""
        try:
            # Encabezado principal
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

            # Campo de búsqueda
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

            # Cuadrícula de categorías
            self.categorias_grid = ft.GridView(
                expand=True,
                runs_count=2,
                max_extent=200,
                child_aspect_ratio=1.0,
                spacing=15,
                run_spacing=15,
            )

            # Estructura de contenido
            self.content = ft.Column([
                self.header_container,
                self.search_field,
                ft.Container(height=10),
                ft.Text("Seleccionar Categoría", size=16, weight=ft.FontWeight.W_600, color=ft.Colors.BLUE_GREY_800),
                self.categorias_grid,
            ], spacing=0, expand=True)
            
            logger.debug("UI construida correctamente")
            
        except Exception as e:
            logger.error(f"Error al construir la interfaz: {e}", exc_info=True)
            self._show_error("Error al construir la interfaz")

    def _load_categorias(self, force_refresh=False):
        db = None
        self.categorias_grid.controls = [ft.ProgressRing()] # Muestra que está cargando
        self.update()

        try:
            logger.info("Cargando categorías...")
            
            db = next(get_db())
            categorias = db.query(Categoria).all()
            
            if not categorias:
                logger.warning("No hay categorías en la base de datos")
                self.categorias_grid.controls = []
            else:
                logger.info(f"Se cargaron {len(categorias)} categorías")
                cards = []
                for c in categorias:
                    try:
                        card = self._create_categoria_card(c)
                        if card:
                            cards.append(card)
                    except Exception as e:
                        logger.error(f"Error al crear tarjeta para categoría {c.id}: {e}")
                        continue
                
                self.categorias_grid.controls = cards
                
                # Guardar en cache
                self._categorias_cache = categorias
            
            if self.page:
                self.page.update()
                
        except Exception as e:
            logger.error(f"Error inesperado al cargar categorías: {e}", exc_info=True)
            self._show_error(f"Error al cargar categorías: {str(e)[:50]}")
            
        finally:
            if db:
                try:
                    db.close()
                except Exception as e:
                    logger.warning(f"Error al cerrar conexión BD: {e}")

    def _create_categoria_card(self, categoria):
        """Crea una tarjeta visual para una categoría."""
        try:
            if not categoria.nombre or not str(categoria.nombre).strip():
                raise ValueError("Categoría sin nombre válido")
            
            return ft.Container(
                content=ft.Column([
                    ft.Icon(ft.Icons.CATEGORY_ROUNDED, size=40, color=ft.Colors.PRIMARY),
                    ft.Text(
                        str(categoria.nombre).upper(), 
                        weight="bold", 
                        size=13, 
                        text_align="center",
                        max_lines=2,
                        overflow=ft.TextOverflow.ELLIPSIS
                    ),
                    ft.Text("Ver productos", size=10, color=ft.Colors.GREY_500),
                ], alignment="center", horizontal_alignment="center", spacing=5),
                bgcolor=ft.Colors.WHITE,
                border_radius=15,
                padding=15,
                on_click=lambda _, c=categoria: self._show_productos(c),
                border=ft.border.all(1, ft.Colors.GREY_200),
                animate_scale=ft.Animation(300, ft.AnimationCurve.EASE_OUT)
            )
        except Exception as e:
            logger.error(f"Error al crear tarjeta de categoría: {e}")
            return None

    def _show_productos(self, categoria):
        """Muestra los productos de una categoría seleccionada."""
        self.categoria_seleccionada = categoria
        logger.info(f"Mostrando productos de categoría: {categoria.nombre}")
        
        header_nav = ft.Row([
            ft.IconButton(ft.Icons.ARROW_BACK_ROUNDED, on_click=lambda _: self._reset_view()),
            ft.Text(categoria.nombre, size=20, weight="bold"),
        ])
        
        self.productos_list = ft.ListView(expand=True, spacing=10, padding=ft.padding.only(top=10))
        self.content.controls = [
            header_nav, 
            self.search_field, 
            self.productos_list
        ]
        
        self._load_productos()
        
        if self.page:
            self.page.update()

    def _load_productos(self, search_term=""):
        """Carga los productos de la categoría seleccionada."""
        if not self.categoria_seleccionada:
            logger.warning("No hay categoría seleccionada")
            return

        db = None
        try:
            logger.info(f"Cargando productos para categoría: {self.categoria_seleccionada.nombre}")
            
            db = next(get_db())
            query = db.query(Producto).filter(
                Producto.categoria_id == self.categoria_seleccionada.id
            )
            
            if search_term:
                search_term = search_term.strip()
                if search_term:
                    query = query.filter(Producto.nombre.ilike(f"%{search_term}%"))
                    logger.debug(f"Buscando productos con término: {search_term}")
            
            productos = query.all()
            
            if not productos:
                logger.info("No hay productos en esta categoría")
                self.productos_list.controls = [
                    ft.Container(
                        content=ft.Text("No hay productos disponibles", color=ft.Colors.GREY_500),
                        padding=20,
                        alignment=ft.alignment.center
                    )
                ]
            else:
                logger.info(f"Se cargaron {len(productos)} productos")
                items = []
                for p in productos:
                    try:
                        item = self._create_producto_item(p)
                        if item:
                            items.append(item)
                    except Exception as e:
                        logger.error(f"Error al crear item para producto {p.id}: {e}")
                        continue
                
                self.productos_list.controls = items
            
            if self.page:
                self.page.update()
                
        except Exception as e:
            logger.error(f"Error al cargar productos: {e}", exc_info=True)
            self._show_error(f"Error al cargar productos: {str(e)[:50]}")
            
        finally:
            if db:
                try:
                    db.close()
                except Exception as e:
                    logger.warning(f"Error al cerrar conexión: {e}")

    def _create_producto_item(self, producto):
        """Crea un item visual para un producto."""
        try:
            # Validar datos del producto
            if not producto.nombre:
                logger.warning(f"Producto sin nombre (id={producto.id})")
                return None
            
            stock = producto.stock_actual or 0
            stock_min = producto.stock_minimo or 0
            
            # Determinar color de stock
            stock_color = ft.Colors.RED_600 if stock < stock_min else ft.Colors.PRIMARY
            
            return ft.Container(
                content=ft.Row([
                    ft.Column([
                        ft.Text(str(producto.nombre), weight="bold", size=15, max_lines=2),
                        ft.Row([
                            ft.Container(
                                content=ft.Text(
                                    f"Stock: {stock}", 
                                    size=11, 
                                    weight="bold", 
                                    color=ft.Colors.WHITE
                                ),
                                bgcolor=stock_color,
                                padding=ft.padding.symmetric(horizontal=8, vertical=2),
                                border_radius=5
                            ),
                            ft.Text(f"Mín: {stock_min}", size=11, color=ft.Colors.GREY_500),
                        ], spacing=10)
                    ], expand=True),
                    ft.IconButton(
                        icon=ft.Icons.ADD_CIRCLE_OUTLINE_ROUNDED, 
                        icon_color=ft.Colors.GREEN_600, 
                        on_click=lambda _, p=producto: self._show_cantidad_dialog(p, "entrada"),
                        tooltip="Registrar Entrada"
                    ),
                    ft.IconButton(
                        icon=ft.Icons.REMOVE_CIRCLE_OUTLINE_ROUNDED, 
                        icon_color=ft.Colors.RED_600, 
                        on_click=lambda _, p=producto: self._show_cantidad_dialog(p, "salida"),
                        tooltip="Registrar Salida"
                    ),
                ], spacing=10),
                padding=12, 
                bgcolor=ft.Colors.WHITE, 
                border_radius=12,
                border=ft.border.all(1, ft.Colors.GREY_200)
            )
        except Exception as e:
            logger.error(f"Error al crear item de producto: {e}")
            return None

    def _show_cantidad_dialog(self, producto, tipo):
        self.producto_seleccionado = producto
        
        cant_input = ft.TextField(
            label="Cantidad", 
            value="1", 
            keyboard_type=ft.KeyboardType.NUMBER,
            autofocus=True
        )

        def al_confirmar(e):
            # 1. Validación básica de UI
            try:
                cantidad = int(cant_input.value)
                if cantidad <= 0: raise ValueError()
            except ValueError:
                cant_input.error_text = "Número entero mayor a 0"
                cant_input.update()
                return

            # 2. Cerrar diálogo primero para dar sensación de rapidez
            self.active_dialog.open = False
            self.page.update()
            
            # 3. Llamar a la lógica de base de datos que ya tienes
            self._registrar_movimiento(tipo, cantidad)

        self.active_dialog = ft.AlertDialog(
            title=ft.Text(f"Registrar {tipo.capitalize()}"),
            content=ft.Column([
                ft.Text(f"Producto: {producto.nombre}"),
                cant_input
            ], tight=True),
            actions=[
                ft.TextButton("Cancelar", on_click=self._close_dialog),
                ft.ElevatedButton("Confirmar", on_click=al_confirmar)
            ]
        )

        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _registrar_movimiento(self, tipo, cantidad):
        """Registra un movimiento (entrada/salida) de producto."""
        db = None
        try:
            # 1. Feedback visual inmediato (opcional, pero recomendado)
            logger.info(f"Iniciando registro de {tipo} para ID: {self.producto_seleccionado.id}")
            
            db = next(get_db())
            
            # Re-obtener el producto dentro de la sesión activa
            prod = db.query(Producto).filter(
                Producto.id == self.producto_seleccionado.id
            ).first()
            
            if not prod:
                logger.error(f"Producto no encontrado: {self.producto_seleccionado.id}")
                self._show_error("Producto no encontrado en la base de datos")
                return

            # Gestión de usuario y auditoría de stock
            user_id = self.page.session.get("user_id") or 1
            cant_anterior = prod.stock_actual or 0 # Asegurar que no sea None
            
            # Calcular cantidad nueva
            if tipo == "entrada":
                cant_nueva = cant_anterior + cantidad
            else:
                if cant_anterior < cantidad:
                    logger.warning(f"Stock insuficiente: {cant_anterior} < {cantidad}")
                    self._show_error("Error: Stock insuficiente")
                    return
                cant_nueva = cant_anterior - cantidad

            # Crear registro de movimiento
            nuevo_mov = Movimiento(
                producto_id=prod.id,
                tipo=tipo,
                cantidad=cantidad,
                cantidad_anterior=cant_anterior,
                cantidad_nueva=cant_nueva,
                registrado_por=user_id,
                fecha_movimiento=datetime.now()
            )
            
            # Actualizar stock
            prod.stock_actual = cant_nueva
            
            # Guardar cambios
            db.add(nuevo_mov)
            db.commit()
            
            logger.info(f"Éxito: {tipo} registrada. Nuevo stock: {cant_nueva}")
            
            # 2. Actualizar la UI
            self._show_message(f"✓ {tipo.capitalize()} registrada: {prod.nombre}")
            
            # Refrescar la lista de productos para ver el nuevo stock
            self._load_productos(search_term=self.search_field.value)
            
        except Exception as e:
            if db:
                db.rollback()
            logger.error(f"Error crítico en registro: {e}", exc_info=True)
            self._show_error(f"Error al guardar: {str(e)[:50]}")
            
        finally:
            if db:
                db.close()
            # 3. Limpieza de seguridad: quitar el diálogo del overlay si aún existe
            if hasattr(self, 'active_dialog') and self.active_dialog in self.page.overlay:
                self.page.overlay.remove(self.active_dialog)
                self.page.update()

    def _reset_view(self):
        """Vuelve a la vista de selección de categorías."""
        logger.info("Volviendo a vista de categorías")
        self.categoria_seleccionada = None
        self._build_ui()
        self._load_categorias()
        if self.page:
            self.page.update()

    def _on_search_change(self, e):
        """Maneja cambios en el campo de búsqueda."""
        if self.categoria_seleccionada:
            self._load_productos(e.control.value)

    def _close_dialog(self, e=None):
        """Cierra el diálogo activo de forma segura."""
        if hasattr(self, 'active_dialog') and self.active_dialog:
            self.active_dialog.open = False
            self.page.update()
            # Opcional: limpiar el overlay para no acumular basura
            # self.page.overlay.remove(self.active_dialog)

    def _show_message(self, texto):
        """Muestra un mensaje de éxito usando SnackBar moderno."""
        snack = ft.SnackBar(
            content=ft.Text(texto),
            bgcolor=ft.Colors.GREEN_700,
            action="OK"
        )
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()

    def _show_error(self, texto):
        """Muestra un mensaje de error usando SnackBar moderno."""
        snack = ft.SnackBar(
            content=ft.Text(texto),
            bgcolor=ft.Colors.RED_700,
            action="Cerrar"
        )
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()