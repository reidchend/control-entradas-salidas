import flet as ft
from usr.theme import get_colors
from usr.models import Requisicion
from usr.database.base import get_db_adaptive
from usr.views.requisiciones.service import RequisicionService


def _c(page):
    return get_colors(page)


class RequisicionDetailDialog:
    def __init__(self, page, req, on_close=None):
        self.page = page
        self.req = req
        self.on_close = on_close
        self.dialog = None

    def show(self):
        colors = _c(self.page)
        db = next(get_db_adaptive())
        try:
            detalles = RequisicionService.get_detalles(db, self.req.id)

            content = ft.Column(spacing=8, scroll=ft.ScrollMode.AUTO)

            for d in detalles:
                content.controls.append(
                    ft.Container(
                        content=ft.Row([
                            ft.Text(d.ingrediente, weight="bold", expand=True),
                            ft.Text(f"{d.cantidad:.2f} {d.unidad}", color=colors['accent']),
                        ]),
                        padding=10,
                        bgcolor=colors['bg'],
                        border_radius=8,
                    )
                )

            if not detalles:
                content.controls.append(
                    ft.Text("No hay productos en esta requisición", color=colors['text_secondary'])
                )

            self.dialog = ft.AlertDialog(
                title=ft.Text(f"Requisición #{self.req.numero}"),
                content=ft.Column([
                    ft.Row([
                        ft.Container(
                            content=ft.Column([
                                ft.Text("Origen", size=11, color=colors['text_secondary']),
                                ft.Text(self.req.origen.capitalize(), weight="bold"),
                            ], spacing=2),
                        ),
                        ft.Icon(ft.Icons.ARROW_FORWARD, color=ft.Colors.GREY_400),
                        ft.Container(
                            content=ft.Column([
                                ft.Text("Destino", size=11, color=colors['text_secondary']),
                                ft.Text(self.req.destino.capitalize(), weight="bold"),
                            ], spacing=2),
                        ),
                    ], spacing=20),
                    ft.Divider(),
                    ft.Text("Productos:", weight="bold"),
                    content,
                    ft.Divider(),
                    ft.Text(f"Estado: {self.req.estado.upper()}", weight="bold", color=colors['accent']),
                    ft.Text(
                        f"Creada: {self.req.fecha_creacion.strftime('%d/%m/%Y %H:%M') if self.req.fecha_creacion else '-'}",
                        size=11, color=colors['text_secondary']
                    ),
                    ft.Text(
                        f"Observaciones: {self.req.observaciones or 'Sin observaciones'}",
                        size=11, color=colors['text_secondary']
                    ),
                ], tight=True, spacing=10),
                actions=[
                    ft.TextButton("Cerrar", on_click=lambda _: self.close()),
                ],
            )

            self.page.overlay.append(self.dialog)
            self.dialog.open = True
            self.page.update()
        finally:
            db.close()

    def close(self):
        if self.dialog:
            self.dialog.open = False
            self.page.update()
        if self.on_close:
            self.on_close()


class CantidadDialog:
    def __init__(self, page, producto, origen, on_confirm):
        self.page = page
        self.producto = producto
        self.origen = origen
        self.on_confirm = on_confirm
        self.dialog = None

    def show(self):
        colors = _c(self.page)
        es_pesable = getattr(self.producto, 'es_pesable', False)

        db = next(get_db_adaptive())
        try:
            disponible = RequisicionService.get_existencia(db, self.producto.id, self.origen)
        finally:
            db.close()

        stock_color = colors['success'] if disponible > 0 else colors['error']
        unidad = self.producto.unidad_medida or 'uds'

        if es_pesable:
            input_field = ft.TextField(
                label="Peso (kg)",
                value="1",
                keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10,
                width=140,
                autofocus=True,
            )
            stock_unidad = "kg"
        else:
            input_field = ft.TextField(
                label=f"Cantidad ({unidad})",
                value="1",
                keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10,
                width=120,
                autofocus=True,
            )
            stock_unidad = unidad

        stock_info = ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.INVENTORY_2_ROUNDED, size=16, color=stock_color),
                ft.Text(
                    f"Disponible: {disponible} {stock_unidad}",
                    size=12, color=stock_color, weight="bold"
                ),
            ], spacing=5),
            bgcolor=colors['card'],
            padding=10,
            border_radius=8,
        )

        pesable_badge = ft.Container()
        if es_pesable:
            pesable_badge = ft.Container(
                content=ft.Row([
                    ft.Icon(ft.Icons.SCALE, size=14, color=colors['warning']),
                    ft.Text("PESABLE", size=10, color=colors['warning'], weight="bold"),
                ], spacing=3),
                bgcolor=colors.get('orange_50', '#2D2D2D'),
                padding=ft.padding.symmetric(horizontal=8, vertical=3),
                border_radius=5,
            )

        def on_agregar(e):
            try:
                valor = float(input_field.value.replace(",", "."))
                if valor <= 0:
                    raise ValueError()
            except:
                input_field.error_text = "Inválido"
                input_field.update()
                return

            if not es_pesable:
                valor = int(valor)

            self.dialog.open = False
            self.page.update()

            self.on_confirm(
                producto_id=self.producto.id,
                nombre=self.producto.nombre,
                cantidad=valor,
                unidad=unidad,
                es_pesable=es_pesable,
            )

        self.dialog = ft.AlertDialog(
            title=ft.Row([
                ft.Text(f"Agregar: {self.producto.nombre}", expand=True),
                pesable_badge,
            ]),
            content=ft.Column([
                stock_info,
                ft.Container(height=10),
                input_field,
                ft.Container(height=5),
            ], tight=True),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: setattr(self.dialog, 'open', False) or self.page.update()),
                ft.ElevatedButton("Agregar", on_click=on_agregar, bgcolor=colors['accent'], color="white"),
            ],
        )

        self.page.overlay.append(self.dialog)
        self.dialog.open = True
        self.page.update()
