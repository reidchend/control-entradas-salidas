import flet as ft
from datetime import datetime, timedelta, date
from usr.database.base import get_db
from usr.models import Factura, Movimiento, Producto
from sqlalchemy.orm import joinedload
from sqlalchemy import func

class HistorialFacturasView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.bgcolor = ft.Colors.GREY_50

        # ── Datos ──────────────────────────────────────────────
        self.facturas_data = []

        # ── Tab 1: Historial de Facturas ───────────────────────
        self.facturas_list = ft.ListView(expand=True, spacing=10, padding=20)
        self.total_facturas_text = ft.Text("0 factura(s)", size=14, weight="w500", color=ft.Colors.GREY_600)

        self.search_field = ft.TextField(
            label="Número o Proveedor",
            prefix_icon=ft.Icons.SEARCH,
            expand=True,
            border_radius=10,
            bgcolor=ft.Colors.WHITE,
            on_change=self._apply_filters,
        )
        self.estado_dropdown = ft.Dropdown(
            label="Estado",
            width=150,
            border_radius=10,
            bgcolor=ft.Colors.WHITE,
            options=[
                ft.dropdown.Option("Todos"),
                ft.dropdown.Option("Validada"),
                ft.dropdown.Option("Pendiente"),
                ft.dropdown.Option("Anulada"),
            ],
            value="Todos",
            on_change=self._apply_filters,
        )

        # ── Tab 2: Entradas por Fecha ──────────────────────────
        self.entradas_list = ft.ListView(expand=True, spacing=10, padding=20)
        self._periodo_seleccionado = "ayer"
        self._periodo_buttons = {}

        self._res_cantidad = ft.Text("0",       size=22, weight="bold", color=ft.Colors.BLUE_700)
        self._res_peso     = ft.Text("0.00 kg", size=22, weight="bold", color=ft.Colors.ORANGE_700)
        self._res_prods    = ft.Text("0",       size=22, weight="bold", color=ft.Colors.GREEN_700)

        self._build_ui()

    # ══════════════════════════════════════════════════════════════
    #  CONSTRUCCION DE LA UI
    # ══════════════════════════════════════════════════════════════
    def _build_ui(self):
        header = ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Text("Historial", size=26, weight="bold", color=ft.Colors.BLUE_GREY_900),
                    ft.Text("Facturas y registro de entradas", size=13, color=ft.Colors.BLUE_GREY_400),
                ], expand=True, spacing=0),
                ft.IconButton(
                    ft.Icons.REFRESH_ROUNDED,
                    icon_color=ft.Colors.BLUE_600,
                    tooltip="Refrescar",
                    on_click=self._on_refresh,
                ),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            padding=ft.padding.only(left=20, right=20, top=20, bottom=10),
        )

        tabs = ft.Tabs(
            selected_index=0,
            animation_duration=250,
            on_change=self._on_tab_change,
            tabs=[
                ft.Tab(
                    text="Facturas",
                    icon=ft.Icons.RECEIPT_LONG_ROUNDED,
                    content=self._build_facturas_tab(),
                ),
                ft.Tab(
                    text="Por Fecha",
                    icon=ft.Icons.CALENDAR_MONTH_ROUNDED,
                    content=self._build_fecha_tab(),
                ),
            ],
            expand=True,
        )

        self.content = ft.Column([header, tabs], expand=True, spacing=0)

    # ─── TAB 1 ────────────────────────────────────────────────────
    def _build_facturas_tab(self):
        filtros = ft.Container(
            content=ft.Row([self.search_field, self.estado_dropdown], spacing=10),
            padding=ft.padding.symmetric(horizontal=20, vertical=8),
            bgcolor=ft.Colors.WHITE,
            margin=ft.margin.symmetric(horizontal=20),
            border_radius=12,
            border=ft.border.all(1, ft.Colors.GREY_200),
        )
        return ft.Column([
            ft.Container(height=10),
            filtros,
            ft.Container(content=self.total_facturas_text, padding=ft.padding.only(left=22, top=8)),
            ft.Container(content=self.facturas_list, expand=True),
        ], expand=True, spacing=0)

    # ─── TAB 2 ────────────────────────────────────────────────────
    def _build_fecha_tab(self):
        periodos = [
            ("Hoy",           "hoy"),
            ("Ayer",          "ayer"),
            ("Antier",        "antier"),
            ("Esta semana",   "semana"),
            ("Semana pasada", "semana_pasada"),
            ("Este mes",      "mes"),
        ]

        chips = []
        for label, key in periodos:
            is_default = (key == self._periodo_seleccionado)
            chip = ft.Container(
                data=key,
                content=ft.Text(
                    label,
                    size=12,
                    weight="bold" if is_default else "normal",
                    color=ft.Colors.WHITE if is_default else ft.Colors.BLUE_GREY_700,
                ),
                bgcolor=ft.Colors.BLUE_600 if is_default else ft.Colors.WHITE,
                border=ft.border.all(1, ft.Colors.BLUE_600 if is_default else ft.Colors.GREY_300),
                border_radius=20,
                padding=ft.padding.symmetric(horizontal=14, vertical=8),
                on_click=lambda e: self._select_periodo(e.control.data),
                animate=150,
            )
            self._periodo_buttons[key] = chip
            chips.append(chip)

        chips_row = ft.Container(
            content=ft.Row(chips, wrap=True, spacing=8, run_spacing=8),
            padding=ft.padding.symmetric(horizontal=20, vertical=12),
        )

        resumen_row = ft.Container(
            content=ft.Row([
                self._stat_mini("Unidades",  self._res_cantidad, ft.Icons.INVENTORY_2_ROUNDED, ft.Colors.BLUE),
                self._stat_mini("Peso total", self._res_peso,    ft.Icons.SCALE_ROUNDED,      ft.Colors.ORANGE),
                self._stat_mini("Productos", self._res_prods,   ft.Icons.CATEGORY_ROUNDED,   ft.Colors.GREEN),
            ], scroll=ft.ScrollMode.HIDDEN, spacing=10),
            padding=ft.padding.symmetric(horizontal=20),
        )

        return ft.Column([
            ft.Container(height=10),
            chips_row,
            resumen_row,
            ft.Container(height=8),
            ft.Container(content=self.entradas_list, expand=True),
        ], expand=True, spacing=0)

    def _stat_mini(self, title, value_ctrl, icon, color):
        return ft.Container(
            content=ft.Row([
                ft.Container(
                    content=ft.Icon(icon, color=color, size=20),
                    bgcolor=ft.Colors.with_opacity(0.1, color),
                    padding=8, border_radius=10,
                ),
                ft.Column([
                    ft.Text(title, size=11, color=ft.Colors.GREY_600),
                    value_ctrl,
                ], spacing=0),
            ], spacing=10),
            bgcolor=ft.Colors.WHITE,
            padding=10,
            border_radius=12,
            border=ft.border.all(1, ft.Colors.GREY_200),
            width=155,
        )

    # ══════════════════════════════════════════════════════════════
    #  CICLO DE VIDA
    # ══════════════════════════════════════════════════════════════
    def did_mount(self):
        self._load_facturas()

    def _on_tab_change(self, e):
        if e.control.selected_index == 1:
            self._load_entradas_por_fecha()

    def _on_refresh(self, e):
        self._load_facturas()
        self._load_entradas_por_fecha()

    # ══════════════════════════════════════════════════════════════
    #  TAB 1 - FACTURAS
    # ══════════════════════════════════════════════════════════════
    def _load_facturas(self):
        db = None
        try:
            db = next(get_db())
            self.facturas_data = (
                db.query(Factura)
                .order_by(Factura.fecha_factura.desc())
                .all()
            )
            self._apply_filters()
        except Exception as e:
            self._show_error(f"Error cargando facturas: {e}")
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
        self._render_facturas(filtered)

    def _render_facturas(self, facturas):
        self.facturas_list.controls.clear()
        self.total_facturas_text.value = f"{len(facturas)} factura(s) encontrada(s)"

        if not facturas:
            self.facturas_list.controls.append(
                ft.Container(
                    content=ft.Column([
                        ft.Icon(ft.Icons.RECEIPT_LONG_OUTLINED, size=48, color=ft.Colors.GREY_300),
                        ft.Text("Sin resultados", color=ft.Colors.GREY_400),
                    ], horizontal_alignment="center"),
                    padding=ft.padding.only(top=80),
                    alignment=ft.alignment.top_center,
                )
            )
        else:
            for f in facturas:
                self.facturas_list.controls.append(self._create_factura_card(f))

        if self.page: self.page.update()

    def _create_factura_card(self, f):
        color_map = {
            "Validada": ft.Colors.GREEN_600,
            "Pendiente": ft.Colors.ORANGE_600,
            "Anulada": ft.Colors.RED_600,
        }
        color = color_map.get(f.estado, ft.Colors.GREY_400)

        return ft.Container(
            padding=15,
            bgcolor=ft.Colors.WHITE,
            border_radius=12,
            border=ft.border.all(1, ft.Colors.GREY_200),
            ink=True,
            on_click=lambda _: self._show_factura_detalle(f),
            content=ft.Column([
                ft.Row([
                    ft.Icon(ft.Icons.RECEIPT_ROUNDED, color=ft.Colors.BLUE_400),
                    ft.Text(f"#{f.numero_factura}", weight="bold", size=16, expand=True),
                    ft.Container(
                        content=ft.Text(f.estado, color="white", size=10, weight="bold"),
                        bgcolor=color,
                        padding=ft.padding.symmetric(horizontal=8, vertical=4),
                        border_radius=5,
                    ),
                ]),
                ft.Text(f"Proveedor: {f.proveedor or 'N/A'}", size=12, color=ft.Colors.BLUE_GREY_400),
                ft.Row([
                    ft.Text(
                        f"Fecha: {f.fecha_factura.strftime('%d/%m/%Y') if f.fecha_factura else 'S/F'}",
                        size=11, expand=True,
                    ),
                    ft.Text(f"${f.total_neto:,.2f}", weight="bold", color=ft.Colors.GREEN_700, size=16),
                    ft.Icon(ft.Icons.KEYBOARD_ARROW_RIGHT, color="grey"),
                ]),
            ], spacing=5),
        )

    def _show_factura_detalle(self, factura):
        def close_dialog(e):
            dialog.open = False
            self.page.update()

        db = None
        try:
            db = next(get_db())
            movimientos = (
                db.query(Movimiento)
                .options(joinedload(Movimiento.producto))
                .filter(Movimiento.factura_id == factura.id)
                .all()
            )

            # Totales de la factura
            total_uds  = sum(m.cantidad for m in movimientos)
            total_peso = sum(m.peso_total or 0 for m in movimientos)
            hay_peso   = any((m.peso_total or 0) > 0 for m in movimientos)

            chips_resumen = [
                ft.Container(
                    content=ft.Row([
                        ft.Icon(ft.Icons.INVENTORY_2_ROUNDED, size=14, color=ft.Colors.WHITE),
                        ft.Text(f"{int(total_uds)} uds", size=12, color=ft.Colors.WHITE, weight="bold"),
                    ], spacing=4),
                    bgcolor=ft.Colors.BLUE_600,
                    padding=ft.padding.symmetric(horizontal=10, vertical=5),
                    border_radius=20,
                ),
            ]
            if hay_peso:
                chips_resumen.append(
                    ft.Container(
                        content=ft.Row([
                            ft.Icon(ft.Icons.SCALE_ROUNDED, size=14, color=ft.Colors.WHITE),
                            ft.Text(f"{total_peso:.2f} kg total", size=12, color=ft.Colors.WHITE, weight="bold"),
                        ], spacing=4),
                        bgcolor=ft.Colors.ORANGE_600,
                        padding=ft.padding.symmetric(horizontal=10, vertical=5),
                        border_radius=20,
                    )
                )

            content_list = ft.Column(spacing=8, tight=True, scroll=ft.ScrollMode.AUTO, width=480)

            if not movimientos:
                content_list.controls.append(
                    ft.Text("No hay productos registrados.", italic=True, color=ft.Colors.GREY_500)
                )
            else:
                for m in movimientos:
                    nombre     = m.producto.nombre if m.producto else "Producto desconocido"
                    unidad     = m.producto.unidad_medida if m.producto else "uds"
                    es_pesable = getattr(m.producto, "es_pesable", False) if m.producto else False
                    peso_val   = m.peso_total or 0

                    peso_badge = ft.Container()
                    if es_pesable and peso_val > 0:
                        peso_badge = ft.Container(
                            content=ft.Row([
                                ft.Icon(ft.Icons.SCALE_ROUNDED, size=12, color=ft.Colors.ORANGE_800),
                                ft.Text(f"{peso_val:.2f} kg", size=11, color=ft.Colors.ORANGE_800, weight="bold"),
                            ], spacing=3),
                            bgcolor=ft.Colors.ORANGE_50,
                            padding=ft.padding.symmetric(horizontal=7, vertical=3),
                            border_radius=5,
                            border=ft.border.all(1, ft.Colors.ORANGE_200),
                        )

                    content_list.controls.append(
                        ft.Container(
                            content=ft.Row([
                                ft.Icon(ft.Icons.SHOPPING_BAG_OUTLINED, size=20, color=ft.Colors.BLUE_400),
                                ft.Column([
                                    ft.Text(nombre, weight="bold", size=13, color=ft.Colors.BLUE_GREY_900),
                                    ft.Row([
                                        ft.Text(f"{int(m.cantidad)} {unidad}", size=12, color=ft.Colors.GREY_600),
                                        peso_badge,
                                    ], spacing=8),
                                ], expand=True, spacing=3),
                            ], spacing=12),
                            padding=10,
                            bgcolor=ft.Colors.GREY_50,
                            border_radius=8,
                            border=ft.border.all(1, ft.Colors.GREY_200),
                        )
                    )

            dialog_content = ft.Column([
                ft.Row(chips_resumen, spacing=8),
                ft.Divider(height=1, color=ft.Colors.GREY_200),
                content_list,
            ], spacing=10, tight=True)

            dialog = ft.AlertDialog(
                title=ft.Row([
                    ft.Icon(ft.Icons.RECEIPT_ROUNDED, color=ft.Colors.BLUE_400),
                    ft.Text(f"Factura #{factura.numero_factura}", weight="bold"),
                ], spacing=8),
                content=ft.Container(content=dialog_content, padding=5),
                actions=[ft.TextButton("Cerrar", on_click=close_dialog)],
            )

            self.page.overlay.append(dialog)
            dialog.open = True
            self.page.update()

        except Exception as e:
            self._show_error(f"No se pudo cargar el detalle: {e}")
        finally:
            if db: db.close()

    # ══════════════════════════════════════════════════════════════
    #  TAB 2 - ENTRADAS POR FECHA
    # ══════════════════════════════════════════════════════════════
    def _get_rango(self, key: str):
        hoy = date.today()
        if key == "hoy":
            inicio = fin = hoy
        elif key == "ayer":
            inicio = fin = hoy - timedelta(days=1)
        elif key == "antier":
            inicio = fin = hoy - timedelta(days=2)
        elif key == "semana":
            inicio = hoy - timedelta(days=hoy.weekday())
            fin    = hoy
        elif key == "semana_pasada":
            lunes_esta = hoy - timedelta(days=hoy.weekday())
            inicio = lunes_esta - timedelta(days=7)
            fin    = lunes_esta - timedelta(days=1)
        elif key == "mes":
            inicio = hoy.replace(day=1)
            fin    = hoy
        else:
            inicio = fin = hoy
        return datetime.combine(inicio, datetime.min.time()), datetime.combine(fin, datetime.max.time())

    def _select_periodo(self, key: str):
        for k, chip in self._periodo_buttons.items():
            is_sel = (k == key)
            chip.bgcolor = ft.Colors.BLUE_600 if is_sel else ft.Colors.WHITE
            chip.border  = ft.border.all(1, ft.Colors.BLUE_600 if is_sel else ft.Colors.GREY_300)
            chip.content.weight = "bold" if is_sel else "normal"
            chip.content.color  = ft.Colors.WHITE if is_sel else ft.Colors.BLUE_GREY_700
            chip.update()
        self._periodo_seleccionado = key
        self._load_entradas_por_fecha()

    def _load_entradas_por_fecha(self):
        db = None
        try:
            dt_inicio, dt_fin = self._get_rango(self._periodo_seleccionado)
            db = next(get_db())
            entradas = (
                db.query(Movimiento)
                .options(joinedload(Movimiento.producto))
                .filter(
                    Movimiento.tipo == "entrada",
                    Movimiento.fecha_movimiento >= dt_inicio,
                    Movimiento.fecha_movimiento <= dt_fin,
                )
                .order_by(Movimiento.fecha_movimiento.desc())
                .all()
            )

            # Resumen
            total_uds  = sum(m.cantidad for m in entradas)
            total_peso = sum(m.peso_total or 0 for m in entradas)
            prods_uniq = len({m.producto_id for m in entradas})

            self._res_cantidad.value = str(int(total_uds))
            self._res_peso.value     = f"{total_peso:.2f} kg"
            self._res_prods.value    = str(prods_uniq)

            self.entradas_list.controls.clear()

            if not entradas:
                self.entradas_list.controls.append(
                    ft.Container(
                        content=ft.Column([
                            ft.Icon(ft.Icons.INBOX_ROUNDED, size=48, color=ft.Colors.GREY_300),
                            ft.Text("Sin entradas en este período", color=ft.Colors.GREY_400, size=14),
                        ], horizontal_alignment="center"),
                        padding=ft.padding.only(top=60),
                        alignment=ft.alignment.top_center,
                    )
                )
            else:
                # Agrupar por dia
                grupos = {}
                for m in entradas:
                    dia = m.fecha_movimiento.strftime("%d/%m/%Y")
                    grupos.setdefault(dia, []).append(m)

                for dia, movs in grupos.items():
                    peso_dia = sum(mv.peso_total or 0 for mv in movs)
                    uds_dia  = sum(mv.cantidad for mv in movs)

                    subtitulo_partes = [f"{int(uds_dia)} uds"]
                    if peso_dia > 0:
                        subtitulo_partes.append(f"{peso_dia:.2f} kg")

                    dia_header = ft.Container(
                        content=ft.Row([
                            ft.Icon(ft.Icons.CALENDAR_TODAY_ROUNDED, size=14, color=ft.Colors.BLUE_GREY_500),
                            ft.Text(dia, size=13, weight="bold", color=ft.Colors.BLUE_GREY_700, expand=True),
                            ft.Text(
                                "  •  ".join(subtitulo_partes),
                                size=11, color=ft.Colors.BLUE_GREY_400, weight="bold",
                            ),
                        ], spacing=6),
                        padding=ft.padding.only(left=4, right=4, bottom=6, top=10),
                    )
                    self.entradas_list.controls.append(dia_header)

                    for m in movs:
                        self.entradas_list.controls.append(self._create_entrada_card(m))

            if self.page: self.page.update()

        except Exception as e:
            self._show_error(f"Error cargando entradas: {e}")
        finally:
            if db: db.close()

    def _create_entrada_card(self, m: Movimiento):
        nombre     = m.producto.nombre if m.producto else "Producto desconocido"
        unidad     = m.producto.unidad_medida if m.producto else "uds"
        es_pesable = getattr(m.producto, "es_pesable", False) if m.producto else False
        peso_val   = m.peso_total or 0

        peso_badge = ft.Container()
        if es_pesable and peso_val > 0:
            peso_badge = ft.Container(
                content=ft.Row([
                    ft.Icon(ft.Icons.SCALE_ROUNDED, size=12, color=ft.Colors.ORANGE_800),
                    ft.Text(f"{peso_val:.2f} kg", size=11, color=ft.Colors.ORANGE_800, weight="bold"),
                ], spacing=3),
                bgcolor=ft.Colors.ORANGE_50,
                padding=ft.padding.symmetric(horizontal=7, vertical=3),
                border_radius=5,
                border=ft.border.all(1, ft.Colors.ORANGE_200),
            )

        if m.factura_id:
            estado_badge = ft.Container(
                content=ft.Row([
                    ft.Icon(ft.Icons.RECEIPT_ROUNDED, size=11, color=ft.Colors.GREEN_800),
                    ft.Text("Validada", size=10, color=ft.Colors.GREEN_800, weight="bold"),
                ], spacing=3),
                bgcolor=ft.Colors.GREEN_50,
                padding=ft.padding.symmetric(horizontal=7, vertical=3),
                border_radius=5,
                border=ft.border.all(1, ft.Colors.GREEN_200),
            )
        else:
            estado_badge = ft.Container(
                content=ft.Text("Pendiente", size=10, color=ft.Colors.ORANGE_800, weight="bold"),
                bgcolor=ft.Colors.ORANGE_50,
                padding=ft.padding.symmetric(horizontal=7, vertical=3),
                border_radius=5,
                border=ft.border.all(1, ft.Colors.ORANGE_200),
            )

        return ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.ADD_CIRCLE_ROUNDED, color=ft.Colors.GREEN_600, size=22),
                ft.Column([
                    ft.Text(nombre, weight="bold", size=14, color=ft.Colors.BLUE_GREY_900,
                            max_lines=1, overflow=ft.TextOverflow.ELLIPSIS),
                    ft.Row([
                        ft.Text(f"{int(m.cantidad)} {unidad}", size=12,
                                color=ft.Colors.BLUE_700, weight="w600"),
                        peso_badge,
                        estado_badge,
                    ], spacing=6),
                ], expand=True, spacing=3),
                ft.Text(m.fecha_movimiento.strftime("%H:%M"), size=11, color=ft.Colors.GREY_400),
            ], spacing=10),
            padding=12,
            bgcolor=ft.Colors.WHITE,
            border_radius=10,
            border=ft.border.all(1, ft.Colors.GREY_200),
        )

    # ══════════════════════════════════════════════════════════════
    #  UTILIDADES
    # ══════════════════════════════════════════════════════════════
    def _show_error(self, m):
        if self.page:
            snack = ft.SnackBar(content=ft.Text(m, color=ft.Colors.WHITE), bgcolor=ft.Colors.RED_700)
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()