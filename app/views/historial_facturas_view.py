import flet as ft
from datetime import datetime
from app.database.base import get_db
from app.models import Factura, Movimiento, Producto
from sqlalchemy.orm import joinedload

class HistorialFacturasView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.bgcolor = ft.Colors.GREY_50
        
        # Estado de datos
        self.facturas_data = []
        
        # Componentes UI
        self.facturas_list = ft.ListView(expand=True, spacing=10, padding=20)
        self.total_text = ft.Text("Iniciando...", size=14, weight="w500")
        self.search_field = ft.TextField(
            label="Número o Proveedor",
            prefix_icon=ft.Icons.SEARCH,
            expand=True,
            on_change=self._apply_filters
        )
        
        self.estado_dropdown = ft.Dropdown(
            label="Estado",
            width=150,
            options=[
                ft.dropdown.Option("Todos"), 
                ft.dropdown.Option("Validada"), 
                ft.dropdown.Option("Pendiente"), 
                ft.dropdown.Option("Anulada")
            ],
            value="Todos",
            on_change=self._apply_filters
        )

        self._build_ui()

    def _build_ui(self):
        self.content = ft.Column([
            ft.Container(
                content=ft.Row([
                    ft.Column([
                        ft.Text("Historial de Facturas", size=28, weight="bold"),
                        self.total_text,
                    ]),
                    ft.IconButton(ft.Icons.REFRESH, on_click=lambda _: self._load_facturas())
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                padding=ft.padding.only(20, 20, 20, 10)
            ),
            ft.Container(
                content=ft.Row([
                    self.search_field, 
                    self.estado_dropdown
                ], spacing=10),
                padding=20, 
                bgcolor=ft.Colors.WHITE, 
                margin=ft.margin.symmetric(horizontal=20),
                border_radius=15, 
                border=ft.border.all(1, ft.Colors.GREY_200)
            ),
            ft.Container(content=self.facturas_list, expand=True)
        ], expand=True)

    def did_mount(self):
        self._load_facturas()

    def _load_facturas(self):
        db = None
        try:
            db = next(get_db())
            self.facturas_data = db.query(Factura).order_by(Factura.fecha_factura.desc()).all()
            self._apply_filters()
        except Exception as e:
            self._show_error(f"Error cargando datos: {e}")
        finally:
            if db: db.close()

    def _apply_filters(self, e=None):
        search = self.search_field.value.lower() if self.search_field.value else ""
        estado = self.estado_dropdown.value
        
        filtered = [
            f for f in self.facturas_data 
            if (search in f.numero_factura.lower() or search in (f.proveedor or "").lower())
            and (estado == "Todos" or f.estado == estado)
        ]
        self._render_list(filtered)

    def _render_list(self, facturas):
        self.facturas_list.controls = []
        self.total_text.value = f"{len(facturas)} factura(s) encontrada(s)"
        
        if not facturas:
            self.facturas_list.controls.append(
                ft.Container(ft.Text("No hay resultados", color="grey"), padding=50, alignment=ft.alignment.center)
            )
        else:
            for f in facturas:
                self.facturas_list.controls.append(self._create_card(f))
        
        if self.page: self.page.update()

    def _create_card(self, f):
        color = {
            "Validada": ft.Colors.GREEN_600,
            "Pendiente": ft.Colors.ORANGE_600,
            "Anulada": ft.Colors.RED_600
        }.get(f.estado, ft.Colors.GREY_400)

        # Usamos GestureDetector o simplemente on_click en Container con feedback visual
        return ft.Container(
            padding=15,
            bgcolor=ft.Colors.WHITE,
            border_radius=12,
            border=ft.border.all(1, ft.Colors.GREY_300),
            ink=True, # Efecto visual de clic (splash)
            on_click=lambda _: self._show_factura_detalle(f),
            content=ft.Column([
                ft.Row([
                    ft.Icon(ft.Icons.RECEIPT, color=ft.Colors.BLUE_400),
                    ft.Text(f"#{f.numero_factura}", weight="bold", size=16, expand=True),
                    ft.Container(
                        content=ft.Text(f.estado, color="white", size=10, weight="bold"),
                        bgcolor=color, padding=ft.padding.symmetric(horizontal=8, vertical=4), border_radius=5
                    )
                ]),
                ft.Text(f"Proveedor: {f.proveedor or 'N/A'}", size=12, color=ft.Colors.BLUE_GREY_400),
                ft.Row([
                    ft.Text(f"Fecha: {f.fecha_factura.strftime('%d/%m/%Y') if f.fecha_factura else 'S/F'}", size=11, expand=True),
                    ft.Text(f"${f.total_neto:,.2f}", weight="bold", color=ft.Colors.GREEN_700, size=16),
                    ft.Icon(ft.Icons.KEYBOARD_ARROW_RIGHT, color="grey")
                ])
            ], spacing=5)
        )

    def _show_factura_detalle(self, factura):
        # Usamos una función interna para manejar el cierre y asegurar el update
        def close_dialog(e):
            dialog.open = False
            self.page.update()

        db = None
        try:
            db = next(get_db())
            movimientos = db.query(Movimiento).options(
                joinedload(Movimiento.producto)
            ).filter(Movimiento.factura_id == factura.id).all()

            content_list = ft.Column(spacing=10, tight=True, scroll=ft.ScrollMode.AUTO, width=500)
            
            if not movimientos:
                content_list.controls.append(ft.Text("No hay productos registrados.", italic=True))
            else:
                for m in movimientos:
                    nombre = m.producto.nombre if m.producto else "Producto desconocido"
                    content_list.controls.append(
                        ft.Container(
                            content=ft.Row([
                                ft.Icon(ft.Icons.SHOPPING_BAG_OUTLINED, size=20, color="blue"),
                                ft.Column([
                                    ft.Text(nombre, weight="bold", size=14),
                                    ft.Text(f"Cantidad: {m.cantidad} | Tipo: {m.tipo}", size=12),
                                ], expand=True),
                            ]),
                            padding=10,
                            bgcolor=ft.Colors.GREY_100,
                            border_radius=8
                        )
                    )

            dialog = ft.AlertDialog(
                title=ft.Text(f"Factura #{factura.numero_factura}"),
                content=content_list,
                actions=[
                    ft.TextButton("Cerrar", on_click=close_dialog)
                ],
            )

            # ESTA PARTE ES CRÍTICA:
            self.page.overlay.append(dialog) # En versiones nuevas es mejor overlay
            dialog.open = True
            self.page.update()

        except Exception as e:
            print(f"Error en detalle: {e}")
            self._show_error(f"No se pudo cargar el detalle: {e}")
        finally:
            if db: db.close()

    def _show_error(self, m):
        if self.page:
            snack = ft.SnackBar(content=ft.Text(m), bgcolor="red")
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()