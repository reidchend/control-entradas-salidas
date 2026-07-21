import flet as ft
from usr.theme import get_colors
from usr.database.base import get_db_adaptive
from usr.notifications import show_success, show_error, show_warning
from usr.views.requisiciones.service import RequisicionService
from usr.views.requisiciones.buscador import ProductoBuscadorSheet
from usr.views.requisiciones.dialogs import CantidadDialog
from usr.views.requisiciones.cards import build_producto_item_row
import logging

logger = logging.getLogger(__name__)


def _c(page):
    return get_colors(page)


class RequisicionForm:
    def __init__(self, page, on_back=None, on_saved=None, requisicion=None):
        self.page = page
        self.on_back = on_back
        self.on_saved = on_saved
        self.requisicion = requisicion

        self.lista_productos_req = []
        self._productos_lista_req = None
        self._origen_dropdown = None
        self._destino_dropdown = None
        self._observaciones_input = None
        self._buscador = None
        self._container = None
        self._productos_count_label = None

        if requisicion:
            self.lista_productos_req = [
                {
                    'producto_id': d.producto_id,
                    'nombre': d.ingrediente,
                    'cantidad': d.cantidad,
                    'unidad': d.unidad,
                    'peso': getattr(d, 'peso', 0),
                    'es_pesable': getattr(d, 'es_pesable', False),
                }
                for d in requisicion.detalles
            ]

    def build(self):
        colors = _c(self.page)

        db = next(get_db_adaptive())
        try:
            almacenes = RequisicionService.get_almacenes(db)
        finally:
            db.close()

        origen_val = self.requisicion.origen if self.requisicion else "principal"
        destino_val = self.requisicion.destino if self.requisicion else "restaurante"

        origen_dropdown = ft.Dropdown(
            label="Desde",
            options=[ft.dropdown.Option(a, a.title()) for a in almacenes],
            value=origen_val,
            border_radius=10,
            expand=True,
        )
        self._origen_dropdown = origen_dropdown

        destino_dropdown = ft.Dropdown(
            label="Hacia",
            options=[ft.dropdown.Option(a, a.title()) for a in almacenes],
            value=destino_val,
            border_radius=10,
            expand=True,
        )
        self._destino_dropdown = destino_dropdown

        almacenes_card = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Icon(ft.Icons.LOCATION_ON_OUTLINED, color=colors['accent'], size=20),
                    ft.Text("Ruta de Traslado", weight="bold", size=14, color=colors['text_primary']),
                ], spacing=10),
                ft.Divider(height=5),
                ft.Row([
                    ft.Column([ft.Text("Desde", size=11, color=colors['text_secondary']), origen_dropdown], expand=True),
                    ft.Icon(ft.Icons.ARROW_FORWARD, color=colors['text_secondary']),
                    ft.Column([ft.Text("Hacia", size=11, color=colors['text_secondary']), destino_dropdown], expand=True),
                ], spacing=10),
            ], spacing=5),
            padding=12,
            bgcolor=colors['card'],
            border_radius=12,
        )

        self._observaciones_input = ft.TextField(
            label="Observaciones",
            hint_text="Notas...",
            border_radius=10,
            multiline=True,
            min_lines=1,
            value=self.requisicion.observaciones if self.requisicion else "",
        )

        productos_lista = ft.ListView(expand=True, spacing=8, padding=10)
        self._productos_lista_req = productos_lista

        boton_agregar = ft.ElevatedButton(
            icon=ft.Icons.ADD,
            text="Agregar Producto",
            on_click=lambda _: self._open_buscador(),
            bgcolor=colors['accent'],
            color="white",
        )

        titulo = "Editar Requisición" if self.requisicion else "Nueva Requisición"
        btn_texto = "Actualizar" if self.requisicion else "Crear"
        btn_color = colors['accent'] if self.requisicion else colors['success']

        header = ft.Container(
            content=ft.Row([
                ft.IconButton(ft.Icons.ARROW_BACK, on_click=lambda _: self._go_back()),
                ft.Text(titulo, size=18, weight="bold", color=colors['text_primary']),
                ft.Container(expand=True),
                ft.ElevatedButton(
                    btn_texto,
                    on_click=lambda _: self._save(),
                    bgcolor=btn_color,
                    color="white",
                ),
            ], spacing=10),
            padding=ft.padding.symmetric(horizontal=10, vertical=8),
            bgcolor=colors['surface'],
        )

        productos_count_label = ft.Text(
            f"Productos ({len(self.lista_productos_req)})",
            weight="bold", size=14, color=colors['text_primary']
        )

        self._productos_count_label = productos_count_label

        panel_productos = ft.Column([
            ft.Row([
                productos_count_label,
                ft.Container(expand=True),
                boton_agregar,
            ], spacing=10),
            ft.Container(
                content=productos_lista,
                bgcolor=colors['bg'],
                border_radius=12,
                expand=True,
                padding=5,
            ),
        ], spacing=5)

        contenido = ft.Column([
            ft.Column([
                header,
                almacenes_card,
            ], spacing=0),
            ft.Container(
                content=ft.Column([
                    self._observaciones_input,
                    ft.Container(height=5),
                    panel_productos,
                ], spacing=5, scroll=ft.ScrollMode.AUTO),
                expand=True,
                padding=ft.padding.only(left=10, right=10, top=5, bottom=10),
            ),
        ], spacing=0, expand=True)

        self._container = ft.Container(
            content=contenido,
            bgcolor=colors['bg'],
            padding=0,
        )

        return self._container

    def _go_back(self):
        if self.on_back:
            self.on_back()

    def _open_buscador(self):
        self._buscador = ProductoBuscadorSheet(
            page=self.page,
            on_product_select=self._on_product_selected,
        )
        self._buscador.show()

    def _on_product_selected(self, producto):
        origen = self._origen_dropdown.value if self._origen_dropdown else "principal"
        dialog = CantidadDialog(
            page=self.page,
            producto=producto,
            origen=origen,
            on_confirm=self._on_cantidad_confirm,
        )
        dialog.show()

    def _on_cantidad_confirm(self, producto_id, nombre, cantidad, unidad, es_pesable):
        existe = next((item for item in self.lista_productos_req if item['producto_id'] == producto_id), None)
        if existe:
            existe['cantidad'] += cantidad
        else:
            self.lista_productos_req.append({
                'producto_id': producto_id,
                'nombre': nombre,
                'cantidad': cantidad,
                'unidad': unidad,
                'es_pesable': es_pesable,
            })

        self._update_productos_list()

        if self._buscador and self._buscador.is_open:
            self._buscador.close()

        show_success(f"+ {nombre}")
        self.page.update()

    def _remove_producto(self, idx):
        if idx < len(self.lista_productos_req):
            self.lista_productos_req.pop(idx)
            self._update_productos_list()

    def _update_productos_list(self):
        colors = _c(self.page)

        if self._productos_count_label:
            self._productos_count_label.value = f"Productos ({len(self.lista_productos_req)})"
            self._productos_count_label.update()

        self._productos_lista_req.controls.clear()

        if not self.lista_productos_req:
            self._productos_lista_req.controls.append(
                ft.Text("Sin productos agregados", color=colors['text_secondary'], text_align="center")
            )
        else:
            for i, item in enumerate(self.lista_productos_req):
                row = build_producto_item_row(item, i, self.page, on_delete=self._remove_producto)
                self._productos_lista_req.controls.append(row)

        self._productos_lista_req.update()

    def _save(self):
        if not self.lista_productos_req:
            show_warning("Agregue al menos un producto")
            self.page.update()
            return

        origen = self._origen_dropdown.value or "principal"
        destino = self._destino_dropdown.value or "restaurante"
        observaciones = self._observaciones_input.value or ""

        db = next(get_db_adaptive())
        try:
            if self.requisicion:
                RequisicionService.update_requisicion(
                    db, self.requisicion, origen, destino, observaciones, self.lista_productos_req
                )
                show_success("Requisición actualizada")
            else:
                user_id = (self.page.session.get("user_id") or "Admin") if self.page else "Admin"
                RequisicionService.create_requisicion(
                    db, origen, destino, observaciones, self.lista_productos_req, user_id
                )
                show_success(f"Requisición creada: {origen} → {destino}")

            self.lista_productos_req = []
            self.page.update()

            if self.on_saved:
                self.on_saved()

        except Exception as ex:
            db.rollback()
            logger.error(f"Error guardando requisición: {ex}")
            show_error(f"Error: {ex}")
            self.page.update()
        finally:
            db.close()
