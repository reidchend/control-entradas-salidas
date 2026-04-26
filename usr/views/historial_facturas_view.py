import asyncio
import flet as ft
import locale
from datetime import datetime, timedelta, date
from usr.database.base import get_db, get_db_adaptive
from usr.database.sync import get_sync_manager
from usr.database.sync_callbacks import register_sync_callback, unregister_sync_callback
from usr.database.cache import get_cache
from usr.models import Factura, Movimiento, Producto
from sqlalchemy.orm import joinedload
from sqlalchemy import func
from usr.theme import get_theme, get_colors


def _colors(page):
    return get_colors(page)


def _c(page, color_name):
    """Mapea colores de ft.Colors a tema dinámico"""
    colors = _colors(page)
    mapping = {
        'GREY_300': colors['text_hint'],
        'GREY_400': colors['text_secondary'],
        'GREY_500': colors['text_secondary'],
        'GREY_600': colors['text_secondary'],
        'GREY_200': colors['border'],
        'GREY_50': colors['bg'],
        'WHITE': colors['white'],
        'BLUE_GREY_900': colors['text_primary'],
        'BLUE_GREY_800': colors['text_primary'],
        'BLUE_GREY_700': colors['text_primary'],
        'BLUE_GREY_500': colors['text_secondary'],
        'BLUE_GREY_400': colors['text_secondary'],
        'BLUE_50': colors.get('blue_50', colors['bg']),
        'BLUE_400': colors['accent'],
        'BLUE_600': colors['accent'],
        'BLUE_700': colors['accent'],
        'GREEN_50': colors.get('green_50', colors['bg']),
        'GREEN_800': colors['success'],
        'GREEN_700': colors['success'],
        'GREEN_600': colors['success'],
        'ORANGE_50': colors.get('orange_50', colors['bg']),
        'ORANGE_200': colors['border'],
        'ORANGE_600': colors['warning'],
        'ORANGE_700': colors['warning'],
        'ORANGE_800': colors['warning'],
        'RED_600': colors['error'],
        'RED_700': colors['error'],
    }
    return mapping.get(color_name, colors['text_primary'])


class HistorialFacturasView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        
        # ── Datos e inicialización ─────────────────────────────
        self.facturas_data = []
        self._periodo_seleccionado = "hoy"
        self._periodo_buttons = {}
        self._fecha_especifica = None

        # Componentes de UI que necesitan persistencia de referencia
        self.facturas_list = ft.ListView(expand=True, spacing=10, padding=20)
        self.entradas_list = ft.ListView(expand=True, spacing=10, padding=20)
        self.total_facturas_text = ft.Text("0 factura(s)", size=14, weight="w500")
        
        self.search_field = ft.TextField(
            hint_text="Buscar número o proveedor...",
            prefix_icon=ft.Icons.SEARCH,
            expand=True,
            border_radius=10,
            on_change=self._apply_filters,
        )
        
        self.clear_search_btn = ft.IconButton(
            icon=ft.Icons.CLEAR,
            on_click=self._clear_search,
            tooltip="Limpiar búsqueda",
        )

        self.fecha_seleccionada_txt = ft.Text("", size=12, weight="bold")

    def on_theme_change(self):
        if not self.page: return
        self._build_ui()
        self._load_facturas()
        self._load_entradas_por_fecha()

    def _build_ui(self):
        colors = _colors(self.page)
        self.bgcolor = colors['bg']
        self.search_field.bgcolor = colors['card']
        self.search_field.border_color = colors['border']
        self.total_facturas_text.color = colors['text_secondary']
        self.fecha_seleccionada_txt.color = colors['accent']
        
        self._connection_indicator = ft.Container(
            content=ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18),
            tooltip="Conectado",
            padding=5,
            on_click=self._on_sync_indicator_click
        )
        
        header = ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Text("Historial", size=26, weight="bold", color=colors['text_primary']),
                    ft.Text("Facturas y registro de entradas", size=13, color=colors['text_secondary']),
                ], expand=True, spacing=0),
                self._connection_indicator,
                ft.IconButton(
                    ft.Icons.REFRESH_ROUNDED,
                    icon_color=colors['accent'],
                    tooltip="Refrescar",
                    on_click=self._on_refresh,
                ),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            padding=ft.padding.only(left=20, right=20, top=20, bottom=10),
            bgcolor=colors['surface'],
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

    def _build_facturas_tab(self):
        colors = _colors(self.page)
        filtros = ft.Container(
            content=ft.Row(
                [self.search_field, self.clear_search_btn], 
                spacing=5,
            ),
            padding=ft.padding.symmetric(horizontal=15, vertical=8),
            bgcolor=colors['card'],
            margin=ft.margin.symmetric(horizontal=10),
            border_radius=12,
            border=ft.border.all(1, colors['border']),
        )
        return ft.Column([
            ft.Container(height=10),
            filtros,
            ft.Container(content=self.total_facturas_text, padding=ft.padding.only(left=22, top=8)),
            ft.Container(content=self.facturas_list, expand=True, bgcolor=colors['bg']),
        ], expand=True, spacing=0)

    def _build_fecha_tab(self):
        colors = _colors(self.page)
        periodos = [
            ("Hoy", "hoy"),
            ("Ayer", "ayer"),
            ("Antier", "antier"),
            ("Esta semana", "semana"),
            ("Este mes", "mes"),
        ]

        # Generar Chips de período
        chips = []
        for label, key in periodos:
            is_active = (key == self._periodo_seleccionado)
            chip = ft.Container(
                data=key,
                content=ft.Text(
                    label,
                    size=11,
                    weight="bold" if is_active else "normal",
                    color=colors['white'] if is_active else colors['text_primary'],
                ),
                bgcolor=colors['accent'] if is_active else colors['card'],
                border=ft.border.all(1, colors['accent'] if is_active else colors['border']),
                border_radius=8,
                padding=ft.padding.symmetric(horizontal=12, vertical=6),
                on_click=lambda e: self._select_periodo(e.control.data),
                animate=150,
            )
            self._periodo_buttons[key] = chip
            chips.append(chip)

        self.fecha_picker_btn = ft.IconButton(
            icon=ft.Icons.CALENDAR_MONTH,
            icon_color=colors['accent'],
            bgcolor=ft.Colors.with_opacity(0.1, colors['accent']),
            on_click=self._show_date_picker,
            tooltip="Elegir fecha específica",
        )

        # Barra Unificada: Calendario | Filtros Rápidos
        selector_row = ft.Container(
            content=ft.Row([
                self.fecha_picker_btn,
                ft.Container(width=1, height=20, bgcolor=colors['border']),
                ft.Row(chips, spacing=5, scroll=ft.ScrollMode.HIDDEN, expand=True),
                self.fecha_seleccionada_txt,
            ], spacing=10),
            padding=ft.padding.symmetric(horizontal=15, vertical=8),
            bgcolor=colors['surface'],
            border=ft.border.only(bottom=ft.border.BorderSide(1, colors['border'])),
        )

        return ft.Column([
            selector_row,
            ft.Container(content=self.entradas_list, expand=True, bgcolor=colors['bg']),
        ], expand=True, spacing=0)

    # ══════════════════════════════════════════════════════════════
    #  LOGICA DE DATOS
    # ══════════════════════════════════════════════════════════════
    def did_mount(self):
        from usr.error_handler import show_error
        try:
            self._build_ui()
            self._load_facturas()
            self._load_entradas_por_fecha()
            self._update_connection_indicator()
        except Exception as e:
            show_error("Error al montar vista", e, "historial_facturas_view.did_mount")
        
        # Hilo de monitoreo
        import threading
        import time
        def check_conn():
            while True:
                time.sleep(10)
                if self.page:
                    self._update_connection_indicator()
                    try: self.page.update()
                    except Exception:
                        pass
        
        t = threading.Thread(target=check_conn, daemon=True)
        t.start()
        
        # Registrar callback para sync automático
        register_sync_callback(self._on_sync_complete)
    
    def will_unmount(self):
        unregister_sync_callback(self._on_sync_complete)
    
    def _on_sync_complete(self):
        if hasattr(self, 'page') and self.page and self.visible:
            async def _reload():
                await asyncio.to_thread(self._load_facturas)
                await asyncio.to_thread(self._load_entradas_por_fecha)
            self.page.run_task(_reload)
    
    def on_sync_complete(self):
        self._on_sync_complete()

    def _on_tab_change(self, e):
        if e.control.selected_index == 1:
            self._load_entradas_por_fecha()

    def _on_refresh(self, e):
        from usr.database.base import is_online
        if is_online():
            sync = get_sync_manager()
            if sync: sync.force_sync_now()
        self._load_facturas()
        self._load_entradas_por_fecha()
        self._show_snack("Actualizado", ft.Colors.GREEN_700)

    def _on_sync_indicator_click(self, e):
        self._update_connection_indicator()
        self.page.update()

    def _show_snack(self, msg, color):
        if not self.page: return
        snack = ft.SnackBar(content=ft.Text(msg, weight="bold"), bgcolor=color)
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()

    def _update_connection_indicator(self):
        from usr.database import get_pending_movimientos_count
        from usr.database.base import is_online
        if not hasattr(self, '_connection_indicator'): return
        pending = get_pending_movimientos_count()
        online = is_online()
        if online:
            self._connection_indicator.content = ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18)
            self._connection_indicator.tooltip = f"Conectado ({pending} pend.)" if pending else "Conectado"
        else:
            self._connection_indicator.content = ft.Icon(ft.Icons.WIFI_OFF, color=ft.Colors.RED_400, size=18)
            self._connection_indicator.tooltip = f"Modo Offline ({pending} pend.)"
        try: self._connection_indicator.update()
        except Exception:
            pass

    # ─── FACTURAS ──────────────────────────────────────────────────
    def _load_facturas(self):
        db = None
        try:
            db = next(get_db_adaptive())
            self.facturas_data = db.query(Factura).order_by(Factura.fecha_factura.desc()).all()
            self._apply_filters()
        except Exception as e:
            self._show_error(f"Error cargando facturas: {str(e)}")
        finally:
            if db: db.close()

    def _apply_filters(self, e=None):
        search = self.search_field.value.lower() if self.search_field.value else ""
        filtered = [f for f in self.facturas_data if search in f.numero_factura.lower() or search in (f.proveedor or "").lower()]
        self._render_facturas(filtered)

    def _clear_search(self, e):
        self.search_field.value = ""
        self._apply_filters()

    def _render_facturas(self, data):
        self.facturas_list.controls.clear()
        self.total_facturas_text.value = f"{len(data)} factura(s) encontradas"
        colors = _colors(self.page)
        
        if not data:
            self.facturas_list.controls.append(
                ft.Container(
                    ft.Column([
                        ft.Icon(ft.Icons.SEARCH_OFF_ROUNDED, size=50, color=_c(self.page, 'GREY_300')),
                        ft.Text("Sin registros", color=colors['text_secondary']),
                    ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),
                    padding=50, alignment=ft.alignment.center
                )
            )
        else:
            for f in data:
                color_est = colors['success'] if f.estado == "Validada" else colors['warning']
                card = ft.Container(
                    padding=15, bgcolor=colors['card'], border_radius=12,
                    border=ft.border.all(1, _c(self.page, 'GREY_200')),
                    ink=True, on_click=lambda _, fact=f: self._show_factura_detalle(fact),
                    content=ft.Column([
                        ft.Row([
                            ft.Icon(ft.Icons.RECEIPT_ROUNDED, color=colors['accent'], size=20),
                            ft.Text(f"#{f.numero_factura}", weight="bold", expand=True, color=colors['text_primary']),
                            ft.Container(ft.Text(f.estado, color="white", size=10, weight="bold"), bgcolor=color_est, padding=ft.padding.symmetric(2, 6), border_radius=4),
                        ]),
                        ft.Text(f.proveedor or "Proveedor No Identificado", size=12, color=colors['text_secondary']),
                        ft.Row([
                            ft.Text(f.fecha_factura.strftime('%d/%m/%Y'), size=11, expand=True, color=_c(self.page, 'GREY_500')),
                            ft.Text(f"${f.total_neto:,.2f}", weight="bold", color=colors['success']),
                        ]),
                    ], spacing=5),
                )
                self.facturas_list.controls.append(card)
        if self.page: self.page.update()

    # ─── ENTRADAS POR FECHA ─────────────────────────────────────────
    def _select_periodo(self, key: str):
        self._fecha_especifica = None
        self.fecha_seleccionada_txt.value = ""
        self._periodo_seleccionado = key
        
        colors = _colors(self.page)
        for k, btn in self._periodo_buttons.items():
            active = (k == key)
            btn.bgcolor = colors['accent'] if active else colors['card']
            btn.border = ft.border.all(1, colors['accent'] if active else colors['border'])
            btn.content.weight = "bold" if active else "normal"
            btn.content.color = colors['white'] if active else colors['text_primary']
            btn.update()
        self._load_entradas_por_fecha()

    def _show_date_picker(self, e):
        def on_date_select(e):
            if e.control.value:
                fecha = e.control.value
                self._fecha_especifica = fecha
                self.fecha_seleccionada_txt.value = f"({fecha.strftime('%d/%m')})"
                self._load_entradas_por_fecha()
                self._clear_period_selection()
        
        picker = ft.DatePicker(
            first_date=datetime(2023, 1, 1),
            last_date=datetime.now(),
            on_change=on_date_select
        )
        self.page.overlay.append(picker)
        picker.open = True
        self.page.update()

    def _clear_period_selection(self):
        colors = _colors(self.page)
        for chip in self._periodo_buttons.values():
            chip.bgcolor = colors['card']
            chip.border = ft.border.all(1, colors['border'])
            chip.content.color = colors['text_primary']
            chip.content.weight = "normal"
            chip.update()

    def _load_entradas_por_fecha(self):
        if not self.page: return
        colors = _colors(self.page)
        
        # Determinar rango
        if self._fecha_especifica:
            ini = datetime.combine(self._fecha_especifica, datetime.min.time())
            fin = ini + timedelta(days=1)
        else:
            hoy = date.today()
            if self._periodo_seleccionado == "hoy": d1 = d2 = hoy
            elif self._periodo_seleccionado == "ayer": d1 = d2 = hoy - timedelta(days=1)
            elif self._periodo_seleccionado == "antier": d1 = d2 = hoy - timedelta(days=2)
            elif self._periodo_seleccionado == "semana": d1 = hoy - timedelta(days=hoy.weekday()); d2 = hoy
            elif self._periodo_seleccionado == "mes": d1 = hoy.replace(day=1); d2 = hoy
            else: d1 = d2 = hoy
            ini = datetime.combine(d1, datetime.min.time())
            fin = datetime.combine(d2, datetime.min.time()) + timedelta(days=1)

        db = None
        try:
            db = next(get_db_adaptive())
            entradas = db.query(Movimiento).options(joinedload(Movimiento.producto)).filter(
                Movimiento.tipo == "entrada", Movimiento.fecha_movimiento >= ini, Movimiento.fecha_movimiento < fin
            ).order_by(Movimiento.fecha_movimiento.desc()).all()

            self.entradas_list.controls.clear()
            if not entradas:
                self.entradas_list.controls.append(
                    ft.Container(ft.Text("Sin movimientos en este periodo", color=colors['text_secondary']), padding=50, alignment=ft.alignment.center)
                )
            else:
                # Agrupar por día
                grupos = {}
                for m in entradas:
                    dia = m.fecha_movimiento.strftime("%d/%m/%Y")
                    grupos.setdefault(dia, []).append(m)

                for dia, movs in grupos.items():
                    uds = sum(mv.cantidad for mv in movs)
                    kg = sum(mv.peso_total or 0 for mv in movs)
                    
                    header_txt = f"{dia}  •  {int(uds)} uds" + (f"  •  {kg:.2f} kg" if kg > 0 else "")
                    self.entradas_list.controls.append(
                        ft.Container(
                            ft.Text(header_txt, size=12, weight="bold", color=_c(self.page, 'GREY_500')),
                            padding=ft.padding.symmetric(horizontal=10, vertical=6),
                            bgcolor=colors['surface'], border_radius=6
                        )
                    )
                    for m in movs:
                        self.entradas_list.controls.append(self._create_entrada_card(m, colors))
            self.update()
        except Exception as e:
            self._show_error(f"Error al cargar movimientos: {str(e)}")
        finally:
            if db: db.close()

    def _create_entrada_card(self, m, colors):
        # Lógica de badges original restaurada
        nombre = m.producto.nombre if m.producto else "Producto Desconocido"
        cantidad = m.cantidad
        unidad = m.producto.unidad_medida if m.producto else "uds"
        fecha_mov = m.fecha_movimiento

        # Corregido: Se eliminó la verificación de id_remoto que causaba AttributeError
        estado_badge = ft.Container()

        peso_badge = ft.Container()
        if m.peso_total and m.peso_total > 0:
            peso_badge = ft.Container(
                content=ft.Text(f"{m.peso_total:.2f} kg", size=10, weight="bold", color=_c(self.page, 'ORANGE_800')),
                bgcolor=_c(self.page, 'ORANGE_50'), padding=ft.padding.symmetric(2, 6), border_radius=5,
                border=ft.border.all(1, _c(self.page, 'ORANGE_200')),
            )

        return ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.ADD_CIRCLE_ROUNDED, color=colors['success'], size=22),
                ft.Column([
                    ft.Text(nombre, weight="bold", size=14, color=colors['text_primary'],
                            max_lines=1, overflow=ft.TextOverflow.ELLIPSIS),
                    ft.Row([
                        ft.Text(f"{int(cantidad)} {unidad}", size=12, color=colors['accent'], weight="w600"),
                        peso_badge,
                        estado_badge,
                    ], spacing=6),
                ], expand=True, spacing=3),
                ft.Text(fecha_mov.strftime("%H:%M"), size=11, color=_c(self.page, 'GREY_400')),
            ], spacing=10),
            padding=12, bgcolor=colors['card'], border_radius=10, border=ft.border.all(1, _c(self.page, 'GREY_200')),
        )

    # ─── DIÁLOGOS Y DETALLES ────────────────────────────────────────
    def _show_factura_detalle(self, f):
        colors = _colors(self.page)
        db = next(get_db_adaptive())
        items = db.query(Movimiento).options(joinedload(Movimiento.producto)).filter(Movimiento.factura_id == f.id).all()
        db.close()

        lista_items = ft.ListView(expand=True, spacing=5)
        for i in items:
            lista_items.controls.append(
                ft.ListTile(
                    leading=ft.Icon(ft.Icons.INVENTORY_2_OUTLINED, size=20, color=colors['accent']),
                    title=ft.Text(i.producto.nombre if i.producto else "Producto", size=13, weight="bold"),
                    subtitle=ft.Text(f"Cant: {int(i.cantidad)} | Peso: {i.peso_total or 0:.2f} kg", size=11),
                    dense=True
                )
            )

        def close_dlg(e):
            dlg.open = False
            self.page.update()

        dlg = ft.AlertDialog(
            title=ft.Text(f"Detalle Factura #{f.numero_factura}"),
            content=ft.Container(
                content=ft.Column([
                    ft.Text(f"Proveedor: {f.proveedor or 'N/A'}", size=14, weight="w500"),
                    ft.Divider(height=20, color=_c(self.page, 'GREY_200')),
                    ft.Text("Productos registrados:", size=12, color=colors['text_secondary']),
                    ft.Container(lista_items, height=300, border=ft.border.all(1, _c(self.page, 'GREY_200')), border_radius=8, padding=5),
                    ft.Row([
                        ft.Text("TOTAL NETO:", weight="bold", color=colors['text_primary']),
                        ft.Text(f"${f.total_neto:,.2f}", weight="bold", color=colors['success'], size=18)
                    ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN)
                ], spacing=10, tight=True),
                width=450
            ),
            actions=[ft.TextButton("Cerrar", on_click=close_dlg)],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.overlay.append(dlg)
        dlg.open = True
        self.page.update()

    def _show_error(self, m):
        if self.page:
            colors = _colors(self.page)
            snack = ft.SnackBar(
                content=ft.Row([ft.Icon(ft.Icons.ERROR_OUTLINE, color="white"), ft.Text(m)], spacing=10),
                bgcolor=colors['error']
            )
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()