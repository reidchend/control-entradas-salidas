import flet as ft
from app.database.base import get_db
from app.models import Producto, Movimiento, Categoria
from datetime import datetime
import logging
from sqlalchemy import func

logger = logging.getLogger(__name__)

class StockView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.bgcolor = ft.Colors.GREY_50
        self.padding = ft.padding.all(0)
        
        # Componentes UI
        self.categoria_filter = None
        self.search_field = None
        self.productos_list = None
        self.summary_container = None
        self.active_dialog = None
        
        # Estado de resumen
        self.total_productos_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_700)
        self.stock_bajo_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.ORANGE_700)
        self.sin_stock_text = ft.Text("0", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.RED_700)

        self._build_ui()
    
    def did_mount(self):
        self._load_categorias()
        self._load_productos()
    
    def _build_ui(self):
        header = ft.Container(
            content=ft.Column([
                ft.Text("Gestión de Stock", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_GREY_900),
                ft.Text("Control e inventario de productos y pesaje", size=14, color=ft.Colors.BLUE_GREY_400),
            ], spacing=2),
            padding=ft.padding.symmetric(horizontal=16, vertical=12)
        )

        self.summary_container = ft.Container(
            content=ft.Row([
                self._build_stat_card("Total", self.total_productos_text, ft.Icons.INVENTORY_2, ft.Colors.BLUE),
                self._build_stat_card("Bajo Stock", self.stock_bajo_text, ft.Icons.WARNING_AMBER, ft.Colors.ORANGE),
                self._build_stat_card("Agotado", self.sin_stock_text, ft.Icons.ERROR_OUTLINE, ft.Colors.RED),
            ], scroll=ft.ScrollMode.HIDDEN, spacing=12),
            padding=ft.padding.symmetric(horizontal=16)
        )

        self.search_field = ft.TextField(
            label="Buscar producto...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=12,
            bgcolor=ft.Colors.WHITE,
            on_change=self._filter_productos,
            border_color=ft.Colors.TRANSPARENT,
            focused_border_color=ft.Colors.BLUE_400,
        )

        self.categoria_filter = ft.Dropdown(
            label="Categoría",
            border_radius=12,
            bgcolor=ft.Colors.WHITE,
            on_change=self._filter_productos,
            border_color=ft.Colors.TRANSPARENT,
        )

        filters_section = ft.Container(
            content=ft.ResponsiveRow([
                ft.Column([self.search_field], col={"xs": 12, "md": 8}),
                ft.Column([self.categoria_filter], col={"xs": 12, "md": 4}),
            ], spacing=12),
            padding=ft.padding.symmetric(horizontal=16, vertical=8),
        )

        self.productos_list = ft.ListView(
            expand=True,
            spacing=12,
            padding=ft.padding.only(left=16, right=16, bottom=80),
        )

        self.content = ft.Column([
            header,
            self.summary_container,
            ft.Container(height=8),
            filters_section,
            self.productos_list
        ], spacing=0, expand=True)

    def _build_stat_card(self, title, value_control, icon, color):
        return ft.Container(
            content=ft.Row([
                ft.Container(
                    content=ft.Icon(icon, color=color, size=24),
                    bgcolor=ft.Colors.with_opacity(0.1, color),
                    padding=10, border_radius=12,
                ),
                ft.Column([
                    ft.Text(title, size=12, color=ft.Colors.GREY_600),
                    value_control
                ], spacing=0)
            ], spacing=12),
            bgcolor=ft.Colors.WHITE,
            padding=12,
            border_radius=16,
            border=ft.border.all(1, ft.Colors.GREY_200),
            width=160,
        )

    def _load_categorias(self):
        db = next(get_db())
        try:
            categorias = db.query(Categoria).filter(Categoria.activo == True).all()
            self.categoria_filter.options = [ft.dropdown.Option("", "Todas")]
            for cat in categorias:
                self.categoria_filter.options.append(ft.dropdown.Option(str(cat.id), cat.nombre))
            self.update()
        finally:
            db.close()

    def _load_productos(self):
        db = next(get_db())
        try:
            productos = db.query(Producto).filter(Producto.activo == True).all()
            self._render_productos(productos)
        finally:
            db.close()

    def _filter_productos(self, e):
        db = next(get_db())
        try:
            query = db.query(Producto).filter(Producto.activo == True)
            if self.categoria_filter.value and self.categoria_filter.value.isdigit():
                query = query.filter(Producto.categoria_id == int(self.categoria_filter.value))
            
            search = self.search_field.value.lower().strip() if self.search_field.value else ""
            if search:
                query = query.filter((Producto.nombre.ilike(f"%{search}%")) | (Producto.codigo.ilike(f"%{search}%")))
            
            self._render_productos(query.all())
        finally:
            db.close()

    def _render_productos(self, productos):
        self.total_productos_text.value = str(len(productos))
        self.stock_bajo_text.value = str(sum(1 for p in productos if 0 < (p.stock_actual or 0) <= (p.stock_minimo or 0)))
        self.sin_stock_text.value = str(sum(1 for p in productos if (p.stock_actual or 0) <= 0))

        self.productos_list.controls.clear()
        
        if not productos:
            self.productos_list.controls.append(ft.Text("No se encontraron productos", color=ft.Colors.GREY_400, text_align="center"))
        else:
            db = next(get_db())
            try:
                for p in productos:
                    stock_actual = p.stock_actual or 0
                    if stock_actual <= 0: color = ft.Colors.RED_600
                    elif stock_actual <= (p.stock_minimo or 0): color = ft.Colors.ORANGE_600
                    else: color = ft.Colors.GREEN_600

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
                                ft.Icon(ft.Icons.SCALE_ROUNDED, size=16, color=ft.Colors.BLUE_600),
                                ft.Text(f"Peso en Stock: {peso_neto:.2f} kg", size=14, weight=ft.FontWeight.W_600, color=ft.Colors.BLUE_800),
                            ], spacing=8),
                            bgcolor=ft.Colors.BLUE_50,
                            border_radius=8,
                            padding=ft.padding.symmetric(horizontal=10, vertical=8),
                            margin=ft.margin.only(top=5, bottom=5)
                        )

                    self.productos_list.controls.append(
                        ft.Container(
                            content=ft.Column([
                                ft.Row([
                                    ft.Column([
                                        ft.Text(p.nombre, weight="bold", size=16, color=ft.Colors.BLUE_GREY_900),
                                        ft.Text(f"Cat: {p.categoria.nombre if p.categoria else 'N/A'}", size=12, color=ft.Colors.GREY_500),
                                    ], spacing=2, expand=True),
                                    ft.Column([
                                        ft.Text(f"{stock_actual:.0f}", color=color, weight="bold", size=20),
                                        ft.Text("uds", color=color, size=10, weight="bold"),
                                    ], horizontal_alignment="center"),
                                ], alignment="spaceBetween"),
                                
                                peso_view,
                                
                                ft.Divider(height=1, color=ft.Colors.GREY_100),
                                
                                ft.Row([
                                    ft.Text(f"Código: {p.codigo or '---'}", size=12, color=ft.Colors.GREY_600),
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
                            bgcolor=ft.Colors.WHITE, 
                            border_radius=12, 
                            border=ft.border.all(1, ft.Colors.GREY_200),
                        )
                    )
            finally:
                db.close()
                
        self.update()

    def _show_producto_details(self, producto: Producto):
        db = next(get_db())
        try:
            movimientos = db.query(Movimiento).filter(Movimiento.producto_id == producto.id).order_by(Movimiento.fecha_movimiento.desc()).limit(20).all()
            mov_list = ft.ListView(height=400, spacing=8)
            for m in movimientos:
                is_entrada = m.tipo == "entrada"
                icon = ft.Icons.ADD_CIRCLE_OUTLINE if is_entrada else ft.Icons.REMOVE_CIRCLE_OUTLINE
                color = ft.Colors.GREEN_600 if is_entrada else ft.Colors.RED_600
                peso_info = f"\n⚖️ Peso: {m.peso_total:.2f} kg" if getattr(m, 'peso_total', 0) > 0 else ""

                mov_list.controls.append(
                    ft.Container(
                        content=ft.ListTile(
                            leading=ft.Icon(icon, color=color, size=28),
                            title=ft.Text(f"{m.tipo.upper()}: {int(m.cantidad)} unidades", weight="bold"),
                            subtitle=ft.Text(f"{m.fecha_movimiento.strftime('%d/%m/%Y %H:%M')}{peso_info}", size=12),
                            trailing=ft.Text(f"{'+' if is_entrada else '-'}{int(m.cantidad)}", color=color, weight="bold"),
                        ),
                        bgcolor=ft.Colors.GREY_50,
                        border_radius=10,
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