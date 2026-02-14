import flet as ft
from app.database.base import get_db
from app.models import Producto, Movimiento, Categoria
from datetime import datetime

class StockView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        # Fondo gris suave para contrastar con las tarjetas blancas
        self.bgcolor = ft.Colors.GREY_50
        self.padding = ft.padding.all(0)
        
        # Componentes UI
        self.categoria_filter = None
        self.search_field = None
        self.productos_list = None
        self.summary_container = None
        self.dialog_producto = None
        
        # Estado de resumen
        self.total_productos_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_700)
        self.stock_bajo_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.ORANGE_700)
        self.sin_stock_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.RED_700)

        self._build_ui()
    
    def did_mount(self):
        """Se ejecuta despues de que la vista se agrega a la pagina"""
        self._load_categorias()
        self._load_productos()
    
    def _build_ui(self):
        """Construir la interfaz de usuario con diseño responsivo"""
        
        # --- 1. ENCABEZADO ---
        header = ft.Container(
            content=ft.Column(
                [
                    ft.Text("Gestión de Stock", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_GREY_900),
                    ft.Text("Control e inventario de productos", size=14, color=ft.Colors.BLUE_GREY_400),
                ],
                spacing=2
            ),
            padding=ft.padding.symmetric(horizontal=16, vertical=12)
        )

        # --- 2. RESUMEN (TARJETAS) ---
        self.summary_container = ft.Container(
            content=ft.Row(
                [
                    self._build_stat_card("Total", self.total_productos_text, ft.Icons.INVENTORY_2, ft.Colors.BLUE),
                    self._build_stat_card("Bajo Stock", self.stock_bajo_text, ft.Icons.WARNING_AMBER, ft.Colors.ORANGE),
                    self._build_stat_card("Agotado", self.sin_stock_text, ft.Icons.ERROR_OUTLINE, ft.Colors.RED),
                ],
                scroll=ft.ScrollMode.HIDDEN,
                spacing=12,
            ),
            padding=ft.padding.symmetric(horizontal=16)
        )

        # --- 3. FILTROS Y BUSCADOR (RESPONSIVO) ---
        self.search_field = ft.TextField(
            label="Buscar producto...",
            hint_text="Nombre o código",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=12,
            bgcolor=ft.Colors.WHITE,
            text_size=14,
            content_padding=12,
            on_change=self._filter_productos,
            border_color=ft.Colors.TRANSPARENT,
            focused_border_color=ft.Colors.BLUE,
        )

        self.categoria_filter = ft.Dropdown(
            label="Categoría",
            icon=ft.Icons.FILTER_LIST,
            border_radius=12,
            bgcolor=ft.Colors.WHITE,
            text_size=14,
            content_padding=10,
            on_change=self._filter_productos,
            border_color=ft.Colors.TRANSPARENT,
            focused_border_color=ft.Colors.BLUE,
        )

        filters_section = ft.Container(
            content=ft.ResponsiveRow(
                [
                    ft.Column([self.search_field], col={"xs": 12, "md": 8}),
                    ft.Column([self.categoria_filter], col={"xs": 12, "md": 4}),
                ],
                spacing=12,
                run_spacing=12,
            ),
            padding=ft.padding.symmetric(horizontal=16, vertical=8),
        )

        # --- 4. LISTA DE PRODUCTOS ---
        self.productos_list = ft.ListView(
            expand=True,
            spacing=12,
            padding=ft.padding.only(left=16, right=16, bottom=80),
        )

        # --- ESTRUCTURA PRINCIPAL ---
        self.content = ft.Column(
            [
                header,
                self.summary_container,
                ft.Container(height=8),
                filters_section,
                ft.Container(height=4),
                self.productos_list
            ],
            spacing=0,
            expand=True
        )

    def _build_stat_card(self, title, value_control, icon, color):
        """Crea una tarjeta de resumen pequeña y estilizada"""
        return ft.Container(
            content=ft.Row(
                [
                    ft.Container(
                        content=ft.Icon(icon, color=color, size=24),
                        bgcolor=ft.Colors.with_opacity(0.1, color),
                        padding=10,
                        border_radius=12,
                    ),
                    ft.Column(
                        [
                            ft.Text(title, size=12, color=ft.Colors.GREY_600, weight=ft.FontWeight.W_500),
                            value_control
                        ],
                        spacing=0,
                        alignment=ft.MainAxisAlignment.CENTER
                    )
                ],
                alignment=ft.MainAxisAlignment.START,
                spacing=12
            ),
            bgcolor=ft.Colors.WHITE,
            padding=12,
            border_radius=16,
            border=ft.border.all(1, ft.Colors.GREY_200),
            width=160,
            shadow=ft.BoxShadow(
                spread_radius=0,
                blur_radius=10,
                color=ft.Colors.with_opacity(0.05, ft.Colors.BLACK),
            )
        )

    def _load_categorias(self):
        try:
            db = next(get_db())
            categorias = db.query(Categoria).filter(Categoria.activo == True).all()
            
            self.categoria_filter.options = [ft.dropdown.Option("", "Todas")]
            for categoria in categorias:
                self.categoria_filter.options.append(
                    ft.dropdown.Option(str(categoria.id), categoria.nombre)
                )
            self.update()
        except Exception as ex:
            print(f"Error cargando categorias: {ex}")
        finally:
            try:
                db.close()
            except:
                pass

    def _load_productos(self):
        try:
            db = next(get_db())
            productos = db.query(Producto).filter(Producto.activo == True).all()
            self._render_productos(productos)
        except Exception as ex:
            print(f"Error cargando productos: {ex}")
            self._show_error("Error al cargar datos")
        finally:
            try:
                db.close()
            except:
                pass

    def _filter_productos(self, e):
        try:
            db = next(get_db())
            query = db.query(Producto).filter(Producto.activo == True)

            # Corrección: Verificar isdigit() para evitar el error con "Todas"
            if self.categoria_filter.value and self.categoria_filter.value.isdigit():
                query = query.filter(Producto.categoria_id == int(self.categoria_filter.value))
            
            search_text = self.search_field.value.lower().strip() if self.search_field.value else ""
            if search_text:
                query = query.filter(
                    (Producto.nombre.ilike(f"%{search_text}%")) | 
                    (Producto.codigo.ilike(f"%{search_text}%"))
                )

            productos = query.all()
            self._render_productos(productos)
        except Exception as ex:
            print(f"Error filtrando: {ex}")
        finally:
            try:
                db.close()
            except:
                pass

    def _render_productos(self, productos):
        """Renderiza la lista de tarjetas de productos"""
        
        # 1. Actualizar Estadísticas
        total = len(productos)
        stock_bajo = sum(1 for p in productos if 0 < p.stock_actual <= p.stock_minimo)
        sin_stock = sum(1 for p in productos if p.stock_actual <= 0)

        self.total_productos_text.value = str(total)
        self.stock_bajo_text.value = str(stock_bajo)
        self.sin_stock_text.value = str(sin_stock)

        # 2. Limpiar lista
        self.productos_list.controls.clear()

        # 3. Estado vacio
        if not productos:
            self.productos_list.controls.append(
                ft.Container(
                    content=ft.Column([
                        ft.Icon(ft.Icons.SEARCH_OFF, size=50, color=ft.Colors.GREY_400),
                        ft.Text("No se encontraron productos", color=ft.Colors.GREY_500)
                    ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),
                    alignment=ft.alignment.center,
                    padding=40
                )
            )
            self.update()
            return

        # 4. Generar Tarjetas
        for p in productos:
            # Lógica de Estado
            if p.stock_actual <= 0:
                status_color = ft.Colors.RED_600
                status_bg = ft.Colors.RED_50
                status_text = "AGOTADO"
                status_icon = ft.Icons.CLOSE
            elif p.stock_actual <= p.stock_minimo:
                status_color = ft.Colors.ORANGE_600
                status_bg = ft.Colors.ORANGE_50
                status_text = "BAJO"
                status_icon = ft.Icons.WARNING_AMBER
            else:
                status_color = ft.Colors.GREEN_600
                status_bg = ft.Colors.GREEN_50
                status_text = "OK"
                status_icon = ft.Icons.CHECK

            # Tarjeta de producto
            card = ft.Container(
                content=ft.Column([
                    # Header
                    ft.Row([
                        ft.Row([
                            ft.Container(
                                content=ft.Icon(ft.Icons.INVENTORY_2_OUTLINED, color=ft.Colors.BLUE_GREY_500),
                                bgcolor=ft.Colors.BLUE_GREY_50,
                                padding=10,
                                border_radius=12
                            ),
                            ft.Column([
                                ft.Text(p.nombre, weight=ft.FontWeight.BOLD, size=16, color=ft.Colors.BLUE_GREY_900),
                                ft.Text(p.categoria.nombre if p.categoria else "Sin categoría", size=12, color=ft.Colors.BLUE_GREY_400)
                            ], spacing=2)
                        ]),
                        ft.Container(
                            content=ft.Row([
                                ft.Icon(status_icon, size=12, color=status_color),
                                ft.Text(status_text, size=11, color=status_color, weight=ft.FontWeight.BOLD)
                            ], spacing=4),
                            bgcolor=status_bg,
                            padding=ft.padding.symmetric(horizontal=8, vertical=4),
                            border_radius=20,
                            border=ft.border.all(1, ft.Colors.with_opacity(0.2, status_color))
                        )
                    ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                    
                    ft.Divider(height=1, color=ft.Colors.GREY_100),
                    
                    # Detalles Stock
                    ft.Row([
                        ft.Column([
                            ft.Text("CÓDIGO", size=10, weight=ft.FontWeight.BOLD, color=ft.Colors.GREY_400),
                            ft.Text(p.codigo or "---", size=14, weight=ft.FontWeight.W_500, color=ft.Colors.GREY_700)
                        ]),
                        ft.Column([
                            ft.Text("STOCK", size=10, weight=ft.FontWeight.BOLD, color=ft.Colors.GREY_400),
                            ft.Row([
                                ft.Text(f"{p.stock_actual:.2f}", size=16, weight=ft.FontWeight.BOLD, color=status_color),
                                ft.Text(p.unidad_medida, size=12, color=ft.Colors.GREY_500)
                            ], vertical_alignment=ft.CrossAxisAlignment.END)
                        ], horizontal_alignment=ft.CrossAxisAlignment.END)
                    ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                    
                    # Acción
                    ft.Container(
                        content=ft.Text("Ver Movimientos", size=12, color=ft.Colors.BLUE_600, weight=ft.FontWeight.W_600),
                        padding=ft.padding.only(top=8),
                        on_click=lambda e, prod=p: self._show_producto_details(prod),
                        alignment=ft.alignment.center_right
                    )
                ], spacing=12),
                bgcolor=ft.Colors.WHITE,
                padding=16,
                border_radius=16,
                border=ft.border.all(1, ft.Colors.GREY_200),
                shadow=ft.BoxShadow(
                    spread_radius=0,
                    blur_radius=4,
                    color=ft.Colors.with_opacity(0.05, ft.Colors.BLACK),
                    offset=ft.Offset(0, 2)
                ),
            )
            self.productos_list.controls.append(card)
        
        self.update()

    def _show_producto_details(self, producto: Producto):
        """Muestra modal con historial completo y estilizado"""
        try:
            db = next(get_db())
            
            # Historial de movimientos recientes
            movimientos = db.query(Movimiento).filter(
                Movimiento.producto_id == producto.id
            ).order_by(Movimiento.fecha_movimiento.desc()).limit(10).all()
            
            # Lista visual de movimientos
            movimientos_list = ft.ListView(
                spacing=8,
                padding=ft.padding.symmetric(vertical=8),
                height=300, # Altura máxima para scroll
            )
            
            if movimientos:
                for mov in movimientos:
                    # Configuración visual según tipo
                    if mov.tipo == "entrada":
                        icon = ft.Icons.ARROW_DOWNWARD
                        icon_bg = ft.Colors.GREEN_50
                        icon_color = ft.Colors.GREEN_700
                        signo = "+"
                    elif mov.tipo == "salida":
                        icon = ft.Icons.ARROW_UPWARD
                        icon_bg = ft.Colors.RED_50
                        icon_color = ft.Colors.RED_700
                        signo = "-"
                    else:
                        icon = ft.Icons.SWAP_HORIZ
                        icon_bg = ft.Colors.BLUE_50
                        icon_color = ft.Colors.BLUE_700
                        signo = ""
                    
                    # Item de la lista de movimientos
                    item = ft.Container(
                        content=ft.Row([
                            ft.Row([
                                ft.Container(
                                    content=ft.Icon(icon, size=16, color=icon_color),
                                    bgcolor=icon_bg,
                                    padding=8,
                                    border_radius=8
                                ),
                                ft.Column([
                                    ft.Text(f"{mov.tipo.capitalize()}", weight=ft.FontWeight.W_600, size=14),
                                    ft.Text(mov.fecha_movimiento.strftime("%d/%m %H:%M"), size=11, color=ft.Colors.GREY_500),
                                ], spacing=2)
                            ]),
                            ft.Text(
                                f"{signo}{mov.cantidad:.2f} {producto.unidad_medida}", 
                                weight=ft.FontWeight.BOLD, 
                                color=icon_color,
                                size=14
                            )
                        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                        bgcolor=ft.Colors.WHITE,
                        padding=12,
                        border_radius=12,
                        border=ft.border.all(1, ft.Colors.GREY_100)
                    )
                    movimientos_list.controls.append(item)
            else:
                movimientos_list.controls.append(
                    ft.Container(
                        content=ft.Column([
                            ft.Icon(ft.Icons.HISTORY, size=40, color=ft.Colors.GREY_300),
                            ft.Text("Sin movimientos recientes", color=ft.Colors.GREY_400)
                        ], alignment=ft.MainAxisAlignment.CENTER),
                        alignment=ft.alignment.center,
                        padding=30
                    )
                )

            # Contenido del diálogo
            content = ft.Container(
                content=ft.Column([
                    # Header del diálogo
                    ft.Row([
                        ft.Column([
                            ft.Text(producto.nombre, size=18, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_GREY_900),
                            ft.Text(f"Código: {producto.codigo or 'N/A'}", size=12, color=ft.Colors.GREY_500),
                        ], spacing=2),
                        ft.Container(
                            content=ft.Text(f"{producto.stock_actual:.2f} {producto.unidad_medida}", weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_600),
                            bgcolor=ft.Colors.BLUE_50,
                            padding=ft.padding.symmetric(horizontal=10, vertical=6),
                            border_radius=8
                        )
                    ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                    
                    ft.Divider(color=ft.Colors.GREY_200),
                    
                    ft.Text("Historial Reciente", size=13, weight=ft.FontWeight.W_600, color=ft.Colors.GREY_700),
                    movimientos_list
                ], spacing=10),
                width=400, # Ancho fijo para PC, se adapta en móvil por el dialogo
                bgcolor=ft.Colors.WHITE,
            )

            self.dialog_producto = ft.AlertDialog(
                content=content,
                content_padding=20,
                shape=ft.RoundedRectangleBorder(radius=16),
                bgcolor=ft.Colors.WHITE,
                actions=[
                    ft.TextButton("Cerrar", on_click=self._close_dialog, style=ft.ButtonStyle(color=ft.Colors.GREY_600))
                ],
                actions_alignment=ft.MainAxisAlignment.END,
            )
            
            self.page.dialog = self.dialog_producto
            self.dialog_producto.open = True
            self.page.update()
            
        except Exception as ex:
            print(f"Error detalles: {ex}")
            self._show_error("Error al cargar detalles")
        finally:
            try:
                db.close()
            except:
                pass

    def _close_dialog(self, e=None):
        if self.dialog_producto:
            self.dialog_producto.open = False
            self.page.update()

    def _show_error(self, msg):
        try:
            self.page.show_snack_bar(ft.SnackBar(content=ft.Text(msg), bgcolor=ft.Colors.RED))
            self.page.update()
        except:
            pass