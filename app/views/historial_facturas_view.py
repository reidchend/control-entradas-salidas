import flet as ft
from datetime import datetime, timedelta
from app.database.base import get_db
from app.models import Factura, Movimiento, Producto, Categoria
from sqlalchemy import or_, and_


class HistorialFacturasView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.bgcolor = ft.colors.GREY_50
        self.padding = 0
        
        # Componentes UI
        self.facturas_list = None
        self.search_numero_field = None
        self.fecha_desde_field = None
        self.fecha_hasta_field = None
        self.proveedor_field = None
        self.estado_dropdown = None
        self.total_facturas_text = None
        
        # Estado
        self.facturas_data = []
        self.factura_seleccionada = None
        
        self._build_ui()
    
    def did_mount(self):
        """Carga inicial al montar el componente"""
        self._load_facturas()
    
    def _build_ui(self):
        # --- HEADER ---
        header = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Column([
                        ft.Text("Historial de Facturas", size=26, weight=ft.FontWeight.BOLD, color=ft.colors.BLUE_GREY_900),
                        ft.Text("Consulta y seguimiento de facturas validadas", size=13, color=ft.colors.BLUE_GREY_400),
                    ], expand=True, spacing=0),
                    ft.IconButton(
                        icon=ft.icons.REFRESH_ROUNDED,
                        icon_color=ft.colors.BLUE_600,
                        on_click=lambda _: self._load_facturas(),
                        tooltip="Refrescar lista"
                    )
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            ], spacing=2),
            padding=ft.padding.only(left=20, top=20, right=20, bottom=10)
        )

        # --- FILTROS DE BÚSQUEDA ---
        self.search_numero_field = ft.TextField(
            hint_text="Número de factura",
            prefix_icon=ft.icons.RECEIPT_LONG_ROUNDED,
            border_radius=12,
            bgcolor=ft.colors.WHITE,
            border_color=ft.colors.GREY_300,
            focused_border_color=ft.colors.BLUE_600,
            height=50,
            text_size=14,
            on_change=self._apply_filters,
        )
        
        self.proveedor_field = ft.TextField(
            hint_text="Proveedor",
            prefix_icon=ft.icons.BUSINESS_ROUNDED,
            border_radius=12,
            bgcolor=ft.colors.WHITE,
            border_color=ft.colors.GREY_300,
            focused_border_color=ft.colors.BLUE_600,
            height=50,
            text_size=14,
            on_change=self._apply_filters,
        )
        
        self.estado_dropdown = ft.Dropdown(
            hint_text="Estado",
            options=[
                ft.dropdown.Option("Todos", "Todos"),
                ft.dropdown.Option("Validada", "Validada"),
                ft.dropdown.Option("Pendiente", "Pendiente"),
                ft.dropdown.Option("Anulada", "Anulada"),
            ],
            value="Todos",
            border_radius=12,
            bgcolor=ft.colors.WHITE,
            border_color=ft.colors.GREY_300,
            focused_border_color=ft.colors.BLUE_600,
            height=50,
            text_size=14,
            on_change=self._apply_filters,
        )
        
        # Inicializar fechas (últimos 30 días por defecto)
        fecha_hasta = datetime.now()
        fecha_desde = fecha_hasta - timedelta(days=30)
        
        self.fecha_desde_field = ft.TextField(
            hint_text="Fecha desde",
            value=fecha_desde.strftime("%Y-%m-%d"),
            prefix_icon=ft.icons.CALENDAR_TODAY_ROUNDED,
            border_radius=12,
            bgcolor=ft.colors.WHITE,
            border_color=ft.colors.GREY_300,
            focused_border_color=ft.colors.BLUE_600,
            height=50,
            text_size=14,
            on_change=self._apply_filters,
        )
        
        self.fecha_hasta_field = ft.TextField(
            hint_text="Fecha hasta",
            value=fecha_hasta.strftime("%Y-%m-%d"),
            prefix_icon=ft.icons.CALENDAR_TODAY_ROUNDED,
            border_radius=12,
            bgcolor=ft.colors.WHITE,
            border_color=ft.colors.GREY_300,
            focused_border_color=ft.colors.BLUE_600,
            height=50,
            text_size=14,
            on_change=self._apply_filters,
        )
        
        # Botón de limpiar filtros
        clear_filters_btn = ft.OutlinedButton(
            text="Limpiar Filtros",
            icon=ft.icons.CLEAR_ALL_ROUNDED,
            on_click=self._clear_filters,
            style=ft.ButtonStyle(
                color=ft.colors.BLUE_700,
                shape=ft.RoundedRectangleBorder(radius=10)
            ),
        )
        
        # Total de facturas
        self.total_facturas_text = ft.Text(
            "0 facturas encontradas",
            size=14,
            weight=ft.FontWeight.W_500,
            color=ft.colors.BLUE_GREY_600,
        )
        
        filters_section = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(self.search_numero_field, expand=2),
                    ft.Container(self.proveedor_field, expand=2),
                    ft.Container(self.estado_dropdown, expand=1),
                ], spacing=10),
                ft.Row([
                    ft.Container(self.fecha_desde_field, expand=1),
                    ft.Container(self.fecha_hasta_field, expand=1),
                    clear_filters_btn,
                ], spacing=10, alignment=ft.MainAxisAlignment.START),
                ft.Row([
                    self.total_facturas_text,
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN)
            ], spacing=12),
            padding=ft.padding.symmetric(horizontal=20, vertical=10),
            bgcolor=ft.colors.GREY_100,
            border_radius=12,
            margin=ft.margin.symmetric(horizontal=20),
        )

        # --- LISTA DE FACTURAS ---
        self.facturas_list = ft.ListView(
            expand=True,
            spacing=10,
            padding=ft.padding.only(left=20, right=20, top=15, bottom=20),
        )

        # --- ENSAMBLADO FINAL ---
        self.content = ft.Column([
            header,
            filters_section,
            self.facturas_list,
        ], spacing=15, expand=True)
    
    def _load_facturas(self):
        """Cargar facturas desde la base de datos"""
        db = None
        try:
            db = next(get_db())
            
            # Consulta base
            query = db.query(Factura).order_by(Factura.fecha_factura.desc())
            
            # Aplicar filtro de fechas por defecto (últimos 30 días)
            if self.fecha_desde_field.value:
                try:
                    fecha_desde = datetime.strptime(self.fecha_desde_field.value, "%Y-%m-%d")
                    query = query.filter(Factura.fecha_factura >= fecha_desde)
                except ValueError:
                    pass
            
            if self.fecha_hasta_field.value:
                try:
                    fecha_hasta = datetime.strptime(self.fecha_hasta_field.value, "%Y-%m-%d")
                    # Agregar 1 día para incluir todo el día de fecha_hasta
                    fecha_hasta = fecha_hasta + timedelta(days=1)
                    query = query.filter(Factura.fecha_factura < fecha_hasta)
                except ValueError:
                    pass
            
            self.facturas_data = query.all()
            self._render_facturas(self.facturas_data)
            
        except Exception as e:
            print(f"[ERROR] Error al cargar facturas: {e}")
            import traceback
            traceback.print_exc()
            self._show_error("Error al cargar facturas")
        finally:
            if db:
                db.close()
    
    def _apply_filters(self, e=None):
        """Aplicar filtros de búsqueda"""
        if not self.facturas_data:
            return
        
        # Obtener valores de filtros
        numero = self.search_numero_field.value.lower() if self.search_numero_field.value else ""
        proveedor = self.proveedor_field.value.lower() if self.proveedor_field.value else ""
        estado = self.estado_dropdown.value if self.estado_dropdown.value != "Todos" else ""
        
        # Filtrar facturas
        facturas_filtradas = self.facturas_data
        
        if numero:
            facturas_filtradas = [f for f in facturas_filtradas if numero in f.numero_factura.lower()]
        
        if proveedor:
            facturas_filtradas = [f for f in facturas_filtradas if f.proveedor and proveedor in f.proveedor.lower()]
        
        if estado:
            facturas_filtradas = [f for f in facturas_filtradas if f.estado == estado]
        
        # Filtrar por fechas
        if self.fecha_desde_field.value:
            try:
                fecha_desde = datetime.strptime(self.fecha_desde_field.value, "%Y-%m-%d")
                facturas_filtradas = [f for f in facturas_filtradas if f.fecha_factura >= fecha_desde]
            except ValueError:
                pass
        
        if self.fecha_hasta_field.value:
            try:
                fecha_hasta = datetime.strptime(self.fecha_hasta_field.value, "%Y-%m-%d")
                fecha_hasta = fecha_hasta + timedelta(days=1)
                facturas_filtradas = [f for f in facturas_filtradas if f.fecha_factura < fecha_hasta]
            except ValueError:
                pass
        
        self._render_facturas(facturas_filtradas)
    
    def _clear_filters(self, e=None):
        """Limpiar todos los filtros"""
        self.search_numero_field.value = ""
        self.proveedor_field.value = ""
        self.estado_dropdown.value = "Todos"
        
        # Resetear fechas a últimos 30 días
        fecha_hasta = datetime.now()
        fecha_desde = fecha_hasta - timedelta(days=30)
        self.fecha_desde_field.value = fecha_desde.strftime("%Y-%m-%d")
        self.fecha_hasta_field.value = fecha_hasta.strftime("%Y-%m-%d")
        
        self._load_facturas()
        
        if self.page:
            self.page.update()
    
    def _render_facturas(self, facturas):
        """Renderizar lista de facturas"""
        self.facturas_list.controls.clear()
        
        # Actualizar contador
        self.total_facturas_text.value = f"{len(facturas)} factura{'s' if len(facturas) != 1 else ''} encontrada{'s' if len(facturas) != 1 else ''}"
        
        if not facturas:
            self.facturas_list.controls.append(
                ft.Container(
                    content=ft.Column([
                        ft.Icon(ft.icons.RECEIPT_LONG_OUTLINED, size=60, color=ft.colors.GREY_400),
                        ft.Text("No se encontraron facturas", size=16, color=ft.colors.GREY_600),
                        ft.Text("Ajusta los filtros o registra nuevas facturas", size=12, color=ft.colors.GREY_400),
                    ], horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=8),
                    alignment=ft.alignment.center,
                    padding=ft.padding.all(40),
                )
            )
        else:
            for factura in facturas:
                self.facturas_list.controls.append(self._create_factura_card(factura))
        
        if self.page:
            self.page.update()
    
    def _create_factura_card(self, factura):
        """Crear tarjeta de factura"""
        # Color según estado
        estado_color = {
            "Validada": ft.colors.GREEN_600,
            "Pendiente": ft.colors.ORANGE_600,
            "Anulada": ft.colors.RED_600,
        }.get(factura.estado, ft.colors.GREY_600)
        
        # Chip de estado
        estado_chip = ft.Container(
            content=ft.Text(factura.estado, size=12, weight=ft.FontWeight.BOLD, color="white"),
            bgcolor=estado_color,
            padding=ft.padding.symmetric(horizontal=12, vertical=4),
            border_radius=12,
        )
        
        # Información de la factura
        fecha_str = factura.fecha_factura.strftime("%d/%m/%Y") if factura.fecha_factura else "N/A"
        proveedor_str = factura.proveedor if factura.proveedor else "Sin proveedor"
        
        # Header de la tarjeta
        card_header = ft.Row([
            ft.Column([
                ft.Text(f"Factura #{factura.numero_factura}", size=16, weight=ft.FontWeight.BOLD, color=ft.colors.BLUE_GREY_900),
                ft.Text(proveedor_str, size=13, color=ft.colors.BLUE_GREY_600),
            ], expand=True, spacing=2),
            estado_chip,
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN)
        
        # Detalles de la factura
        detalles = ft.Row([
            ft.Row([
                ft.Icon(ft.icons.CALENDAR_TODAY_ROUNDED, size=16, color=ft.colors.BLUE_600),
                ft.Text(fecha_str, size=13, color=ft.colors.BLUE_GREY_700),
            ], spacing=5),
            ft.Row([
                ft.Icon(ft.icons.ATTACH_MONEY_ROUNDED, size=16, color=ft.colors.GREEN_600),
                ft.Text(f"${factura.total_neto:,.2f}", size=13, weight=ft.FontWeight.W_500, color=ft.colors.BLUE_GREY_800),
            ], spacing=5),
        ], spacing=20)
        
        # Botón para ver detalles
        ver_detalles_btn = ft.ElevatedButton(
            text="Ver Productos",
            icon=ft.icons.VISIBILITY_ROUNDED,
            style=ft.ButtonStyle(
                bgcolor=ft.colors.BLUE_600,
                color="white",
                shape=ft.RoundedRectangleBorder(radius=8),
            ),
            on_click=lambda e, f=factura: self._show_factura_detalle(f),
        )
        
        # Validación info (si está validada)
        validacion_info = None
        if factura.estado == "Validada" and factura.fecha_validacion:
            fecha_validacion = factura.fecha_validacion.strftime("%d/%m/%Y %H:%M")
            validado_por = factura.validada_por if factura.validada_por else "Sistema"
            validacion_info = ft.Container(
                content=ft.Row([
                    ft.Icon(ft.icons.CHECK_CIRCLE_ROUNDED, size=14, color=ft.colors.GREEN_600),
                    ft.Text(f"Validada por {validado_por} el {fecha_validacion}", size=11, color=ft.colors.GREEN_700, italic=True),
                ], spacing=5),
                padding=ft.padding.only(top=8),
            )
        
        # Observaciones (si existen)
        observaciones_info = None
        if factura.observaciones:
            observaciones_info = ft.Container(
                content=ft.Column([
                    ft.Text("Observaciones:", size=12, weight=ft.FontWeight.W_500, color=ft.colors.BLUE_GREY_700),
                    ft.Text(factura.observaciones, size=11, color=ft.colors.BLUE_GREY_600, italic=True),
                ], spacing=3),
                padding=ft.padding.only(top=8),
            )
        
        # Construir contenido de la tarjeta
        card_content = [card_header, detalles]
        if validacion_info:
            card_content.append(validacion_info)
        if observaciones_info:
            card_content.append(observaciones_info)
        card_content.append(ft.Container(
            content=ver_detalles_btn,
            alignment=ft.alignment.center_right,
            padding=ft.padding.only(top=10),
        ))
        
        # Tarjeta completa
        return ft.Container(
            content=ft.Column(card_content, spacing=8),
            bgcolor=ft.colors.WHITE,
            border=ft.border.all(1, ft.colors.GREY_300),
            border_radius=12,
            padding=ft.padding.all(15),
            shadow=ft.BoxShadow(
                spread_radius=0,
                blur_radius=4,
                color=ft.colors.with_opacity(0.1, ft.colors.BLACK),
                offset=ft.Offset(0, 2),
            ),
        )
    
    def _show_factura_detalle(self, factura):
        """Mostrar diálogo con detalles de la factura"""
        db = None
        try:
            db = next(get_db())
            
            # Obtener movimientos asociados a la factura
            movimientos = db.query(Movimiento).filter(
                Movimiento.factura_id == factura.id
            ).all()
            
            # Crear lista de productos
            productos_list = ft.ListView(
                spacing=8,
                height=300,
            )
            
            if not movimientos:
                productos_list.controls.append(
                    ft.Container(
                        content=ft.Text(
                            "No hay productos registrados en esta factura",
                            size=14,
                            color=ft.colors.GREY_600,
                            text_align=ft.TextAlign.CENTER,
                        ),
                        padding=ft.padding.all(20),
                    )
                )
            else:
                for mov in movimientos:
                    producto = db.query(Producto).filter(Producto.id == mov.producto_id).first()
                    if producto:
                        categoria = db.query(Categoria).filter(Categoria.id == producto.categoria_id).first()
                        
                        producto_card = ft.Container(
                            content=ft.Row([
                                ft.Column([
                                    ft.Text(producto.nombre, size=14, weight=ft.FontWeight.W_500, color=ft.colors.BLUE_GREY_900),
                                    ft.Text(
                                        f"{categoria.nombre if categoria else 'Sin categoría'} • {mov.tipo.capitalize()}",
                                        size=12,
                                        color=ft.colors.BLUE_GREY_500,
                                    ),
                                ], expand=True, spacing=2),
                                ft.Column([
                                    ft.Text(
                                        f"{mov.cantidad} {producto.unidad_medida}",
                                        size=14,
                                        weight=ft.FontWeight.BOLD,
                                        color=ft.colors.BLUE_600,
                                    ),
                                    ft.Text(
                                        mov.fecha_movimiento.strftime("%d/%m/%Y %H:%M"),
                                        size=11,
                                        color=ft.colors.BLUE_GREY_400,
                                    ),
                                ], horizontal_alignment=ft.CrossAxisAlignment.END, spacing=2),
                            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                            bgcolor=ft.colors.GREY_50,
                            border=ft.border.all(1, ft.colors.GREY_200),
                            border_radius=8,
                            padding=ft.padding.all(12),
                        )
                        productos_list.controls.append(producto_card)
            
            # Información de la factura
            info_section = ft.Container(
                content=ft.Column([
                    ft.Row([
                        ft.Text("Número:", size=13, weight=ft.FontWeight.W_500, color=ft.colors.BLUE_GREY_700),
                        ft.Text(factura.numero_factura, size=13, color=ft.colors.BLUE_GREY_900),
                    ], spacing=5),
                    ft.Row([
                        ft.Text("Proveedor:", size=13, weight=ft.FontWeight.W_500, color=ft.colors.BLUE_GREY_700),
                        ft.Text(factura.proveedor if factura.proveedor else "N/A", size=13, color=ft.colors.BLUE_GREY_900),
                    ], spacing=5),
                    ft.Row([
                        ft.Text("Fecha:", size=13, weight=ft.FontWeight.W_500, color=ft.colors.BLUE_GREY_700),
                        ft.Text(factura.fecha_factura.strftime("%d/%m/%Y"), size=13, color=ft.colors.BLUE_GREY_900),
                    ], spacing=5),
                    ft.Row([
                        ft.Text("Total:", size=13, weight=ft.FontWeight.W_500, color=ft.colors.BLUE_GREY_700),
                        ft.Text(f"${factura.total_neto:,.2f}", size=13, weight=ft.FontWeight.BOLD, color=ft.colors.GREEN_600),
                    ], spacing=5),
                    ft.Row([
                        ft.Text("Estado:", size=13, weight=ft.FontWeight.W_500, color=ft.colors.BLUE_GREY_700),
                        ft.Container(
                            content=ft.Text(factura.estado, size=12, weight=ft.FontWeight.BOLD, color="white"),
                            bgcolor={
                                "Validada": ft.colors.GREEN_600,
                                "Pendiente": ft.colors.ORANGE_600,
                                "Anulada": ft.colors.RED_600,
                            }.get(factura.estado, ft.colors.GREY_600),
                            padding=ft.padding.symmetric(horizontal=10, vertical=3),
                            border_radius=10,
                        ),
                    ], spacing=5),
                ], spacing=8),
                bgcolor=ft.colors.BLUE_50,
                border_radius=8,
                padding=ft.padding.all(12),
            )
            
            # Diálogo
            dialog = ft.AlertDialog(
                modal=True,
                title=ft.Text(f"Detalle de Factura #{factura.numero_factura}", weight=ft.FontWeight.BOLD),
                content=ft.Container(
                    content=ft.Column([
                        info_section,
                        ft.Divider(height=1, color=ft.colors.GREY_300),
                        ft.Text("Productos:", size=15, weight=ft.FontWeight.W_600, color=ft.colors.BLUE_GREY_800),
                        productos_list,
                    ], spacing=12, tight=True),
                    width=600,
                ),
                actions=[
                    ft.TextButton("Cerrar", on_click=lambda e: self._close_dialog()),
                ],
                actions_alignment=ft.MainAxisAlignment.END,
            )
            
            self.page.dialog = dialog
            dialog.open = True
            self.page.update()
            
        except Exception as e:
            print(f"[ERROR] Error al mostrar detalle de factura: {e}")
            import traceback
            traceback.print_exc()
            self._show_error("Error al cargar detalles de la factura")
        finally:
            if db:
                db.close()
    
    def _close_dialog(self):
        """Cerrar diálogo"""
        if self.page.dialog:
            self.page.dialog.open = False
            self.page.update()
    
    def _show_error(self, mensaje):
        """Mostrar mensaje de error"""
        snack = ft.SnackBar(
            content=ft.Text(mensaje, color="white"),
            bgcolor=ft.colors.RED_600,
        )
        self.page.snack_bar = snack
        snack.open = True
        self.page.update()
