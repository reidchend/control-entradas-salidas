import flet as ft
from datetime import datetime
from usr.database.base import get_db
from usr.models import Movimiento, Factura,Producto, Categoria, Existencia
from usr.logger import get_logger
from usr.theme import get_theme, get_colors

logger = get_logger(__name__)


def _fmt_datetime(dt):
    """Formatea fecha datetime de forma segura."""
    if dt is None:
        return "Sin fecha"
    try:
        return dt.strftime("%d/%m %H:%M")
    except:
        return "Sin fecha"


def _colors(page):
    return get_colors(page)

class ValidacionView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.bgcolor = '#1A1A1A'
        self.padding = 0
        self.is_loading = False
        self.cards_dict = {}
        
        # Componentes UI
        self.entradas_list = ft.ListView(
            expand=True,
            spacing=10,
            padding=ft.padding.only(left=15, right=15, bottom=20),
        )
        self.search_field = None
        self.validate_button = None
        self.clear_button = None
        self.active_dialog = None
        
        # Estado
        self.selected_entradas = set()
        self.entradas_data = {}
        
    def on_theme_change(self):
        """Se llama cuando cambia el tema"""
        if not self.page or not self.page.client_storage:
            return
        colors = _colors(self.page)
        self.bgcolor = colors['bg']
        try:
            self._build_ui()
            self._load_entradas_pendientes()
        except:
            pass
    
    def update_view(self):
        """Refrescar datos"""
        self._load_entradas_pendientes()

    def _on_refresh(self):
        """Refresca la lista - hace sync solo si está online"""
        if self.page:
            from usr.database.base import is_online as base_is_online
            from usr.database import get_sync_manager
            
            online = base_is_online()
            
            if online:
                sync_mgr = get_sync_manager()
                if sync_mgr:
                    sync_mgr.force_sync_now()
            
            snack = ft.SnackBar(
                content=ft.Text("🔄 Actualizando..."),
                bgcolor=ft.Colors.BLUE_600,
                duration=1,
            )
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
        self._load_entradas_pendientes()
    
    async def _on_sync_indicator_click(self, e=None):
        """Solo actualiza el indicador visual"""
        from usr.database import get_sync_manager
        
        sync_mgr = get_sync_manager()
        if not sync_mgr or not self.page:
            return
        
        self._update_connection_indicator()
        self.page.update()
    
    def _show_snack_bar(self, message, bgcolor):
        """Muestra SnackBar."""
        if not self.page:
            return
        snack = ft.SnackBar(
            content=ft.Text(message, weight=ft.FontWeight.BOLD),
            bgcolor=bgcolor,
            duration=5,
        )
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()
    
    def _update_connection_indicator(self):
        from usr.database import get_sync_manager, get_pending_movimientos_count
        from usr.database.base import is_online as base_is_online
        
        if not hasattr(self, '_connection_indicator'):
            return
        
        pending = get_pending_movimientos_count()
        
        online = base_is_online()
        
        if online:
            self._connection_indicator.content = ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18)
            self._connection_indicator.tooltip = f"Conectado - {pending} cambios pendientes" if pending else "Conectado"
        else:
            self._connection_indicator.content = ft.Icon(ft.Icons.WIFI_OFF, color=ft.Colors.RED_400, size=18)
            self._connection_indicator.tooltip = f"Modo offline - {pending} cambios pendientes"
        
        try:
            self._connection_indicator.update()
        except:
            pass
        
        self._connection_indicator.update()

    def did_mount(self):
        """Carga inicial: construye la UI y luego carga los datos"""
        self._build_ui()
        if self.page and self.page.client_storage:
            self._load_entradas_pendientes()
        
        self._update_connection_indicator()
    
    def _build_ui(self):
        colors = _colors(self.page)
        
        self._connection_indicator = ft.Container(
            content=ft.Icon(ft.Icons.WIFI, color=ft.Colors.GREEN_400, size=18),
            tooltip="Conectado",
            padding=5,
            on_click=self._on_sync_indicator_click
        )
        
        header = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Column([
                        ft.Text("Validación", size=26, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                        ft.Text("Vincular entradas a facturas", size=13, color=colors['text_secondary']),
                    ], expand=True, spacing=0),
                    self._connection_indicator,
                    ft.IconButton(
                        icon=ft.Icons.REFRESH_ROUNDED,
                        icon_color=colors['text_secondary'],
                        on_click=lambda _: self._on_refresh(),
                        tooltip="Refrescar lista"
                    )
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            ], spacing=2),
            padding=ft.padding.only(left=20, top=20, right=20, bottom=10)
        )

        self.search_field = ft.TextField(
            hint_text="Buscar producto...",
            prefix_icon=ft.Icons.SEARCH_ROUNDED,
            border_radius=12,
            border_color=colors['input_border'],
            focused_border_color=colors['accent'],
            height=45,
            text_size=14,
            content_padding=ft.padding.symmetric(horizontal=15),
            on_change=self._filter_entradas,
        )

        self.validate_button = ft.ElevatedButton(
            text="Validar (0)",
            icon=ft.Icons.FACT_CHECK_ROUNDED,
            color="white",
            bgcolor=colors['accent'],
            disabled=True,
            style=ft.ButtonStyle(shape=ft.RoundedRectangleBorder(radius=10)),
            on_click=self._show_validar_dialog,
        )
        
        self.clear_button = ft.TextButton(
            text="Limpiar",
            icon=ft.Icons.CLOSE_ROUNDED,
            style=ft.ButtonStyle(color=colors['text_secondary']),
            on_click=self._clear_selection,
            visible=False
        )

        controls_section = ft.Container(
            content=ft.Column([
                self.search_field,
                ft.Row([self.validate_button, self.clear_button], alignment=ft.MainAxisAlignment.SPACE_BETWEEN)
            ], spacing=10),
            padding=ft.padding.symmetric(horizontal=20, vertical=10),
        )

        self.content = ft.Column([
            header,
            controls_section,
            self.entradas_list
        ], spacing=0, expand=True)

    def _create_entrada_card(self, entrada: Movimiento):
        is_selected = entrada.id in self.selected_entradas
        colors = _colors(self.page)
        
        # 1. Badge de Almacén (más sutil)
        almacen_nombre = getattr(entrada, 'almacen', None) or 'principal'
        almacen_badge = ft.Text(
            f"📦 {almacen_nombre.title()}",
            size=10,
            color=colors['text_secondary'],
        )

        # 2. Lógica de Peso (solo si hay peso)
        peso_valor = getattr(entrada, "peso_total", 0) or 0
        peso_badge = ft.Text()
        if peso_valor > 0.001:
            peso_badge = ft.Text(
                f"⚖️ {peso_valor:.3f} kg",
                size=10,
                color='#FF9800',
            )

        # 3. Icono de selección (guardamos referencia)
        check_icon = ft.Icon(
            ft.Icons.CHECK_CIRCLE_ROUNDED if is_selected else ft.Icons.RADIO_BUTTON_UNCHECKED_ROUNDED,
            color=colors['accent'] if is_selected else colors['text_hint'],
            size=22
        )

        def on_eliminar(e):
            self._eliminar_entrada(entrada)
        
        # 3. Construcción de la Card
        card = ft.Container(
            content=ft.Row([
                ft.Container(content=check_icon, padding=2),
                ft.Column([
                    ft.Text(
                        entrada.producto.nombre if entrada.producto else "Producto sin nombre",
                        weight=ft.FontWeight.BOLD, size=15, color=colors['text_primary'],
                        max_lines=1, overflow=ft.TextOverflow.ELLIPSIS
                    ),
                    ft.Row([
                        ft.Text(f"{entrada.cantidad} {entrada.producto.unidad_medida if entrada.producto else 'uds'}", 
                                size=13, weight="w600", color=colors['success']),
                        peso_badge,
                        ft.Container(expand=True),
                        ft.Text(
                            entrada.fecha_movimiento.strftime("%d/%m %H:%M") 
                            if entrada.fecha_movimiento else "Sin fecha",
                            size=11, 
                            color=colors['text_secondary']
                        ),
                    ], spacing=8, vertical_alignment="center"),
                    almacen_badge,
                ], expand=True, spacing=2),
                ft.IconButton(
                    icon=ft.Icons.DELETE_OUTLINE_ROUNDED,
                    icon_color=colors['error'],
                    tooltip="Eliminar entrada",
                    on_click=on_eliminar,
                )
            ], spacing=8),
            padding=15,
            animate=200,
            bgcolor=colors['card_hover'] if is_selected else colors['card'],
            border_radius=12,
            border=ft.border.all(2, colors['accent']) if is_selected else ft.border.all(1, colors['border']),
            on_click=lambda _: self._toggle_entrada_selection(entrada.id)
        )
        
        # Guardamos referencias para actualizar sin reconstruir
        self.cards_dict[entrada.id] = (card, check_icon)
        return card

    def _load_entradas_pendientes(self):

        if self.is_loading:
            return

        self.is_loading = True

        db = None
        try:
            self.entradas_list.controls = [ft.ProgressBar(color="blue")]
            self.update()
            db = next(get_db())
            query = db.query(Movimiento).filter(
                Movimiento.tipo == "entrada",
                Movimiento.factura_id.is_(None)
            )
            
            search_term = ""
            if self.search_field and hasattr(self.search_field, 'value') and self.search_field.value:
                search_term = self.search_field.value.lower().strip()
            
            if search_term:
                query = query.join(Producto).filter(Producto.nombre.ilike(f"%{search_term}%"))
            
            entradas = query.order_by(Movimiento.fecha_movimiento.desc()).all()
            self.entradas_data = {e.id: e for e in entradas}
            
            self.entradas_list.controls.clear()
            if not entradas:
                self.entradas_list.controls.append(
                    ft.Container(
                        content=ft.Column([
                            ft.Icon(ft.Icons.FACT_CHECK_OUTLINED, size=50, color=ft.Colors.GREY_300),
                            ft.Text("Sin entradas pendientes", color=ft.Colors.GREY_400)
                        ], horizontal_alignment="center"),
                        padding=ft.padding.only(top=100),
                        alignment="center"
                    )
                )
            else:
                for ent in entradas:
                    self.entradas_card = self._create_entrada_card(ent)
                    self.entradas_list.controls.append(self.entradas_card)
            
            self._update_validate_button_state()
            if self.page and self.page.client_storage: self.page.update()
        except Exception as ex:
            import traceback
            logger.error(f"Error cargando entradas: {ex}\n{traceback.format_exc()}")
        finally:
            if db: db.close()
            self.is_loading = False
            if self.page and self.page.client_storage:
                self.update()

    def _toggle_entrada_selection(self, eid):
        if eid not in self.cards_dict:
            return

        card, icon = self.cards_dict[eid]
        colors = _colors(self.page)

        if eid in self.selected_entradas:
            # DESELECCIONAR
            self.selected_entradas.remove(eid)
            card.bgcolor = colors['card']
            card.border = ft.border.all(1, colors['border'])
            icon.name = ft.Icons.RADIO_BUTTON_UNCHECKED_ROUNDED
            icon.color = colors['text_hint']
        else:
            # SELECCIONAR
            self.selected_entradas.add(eid)
            card.bgcolor = colors['card_hover']
            card.border = ft.border.all(2, colors['accent'])
            icon.name = ft.Icons.CHECK_CIRCLE_ROUNDED
            icon.color = colors['accent']

        card.update()
        self._update_validate_button_state()
        self.validate_button.update()
        if self.clear_button:
            self.clear_button.update()

    def _update_validate_button_state(self):
        if not self.validate_button or not self.clear_button:
            return
        count = len(self.selected_entradas)
        self.validate_button.text = f"Validar ({count})"
        self.validate_button.disabled = count == 0
        self.clear_button.visible = count > 0

    def _clear_selection(self, e):
        self.selected_entradas.clear()
        self._load_entradas_pendientes()

    def _filter_entradas(self, e):
        self._load_entradas_pendientes()

    def _eliminar_entrada(self, entrada: Movimiento):
        producto_nombre = entrada.producto.nombre if entrada.producto else "este producto"
        
        def on_confirmar(e):
            self._close_dialog()
            db = next(get_db())
            try:
                almacen = getattr(entrada, 'almacen', 'principal') or 'principal'
                
                # Obtener existencia actual
                existencia = db.query(Existencia).filter(
                    Existencia.producto_id == entrada.producto_id,
                    Existencia.almacen == almacen
                ).first()
                
                if existencia:
                    existencia.cantidad = max(0, existencia.cantidad - entrada.cantidad)
                
                # Eliminar el movimiento
                db.delete(entrada)
                db.commit()
                
                snack = ft.SnackBar(
                    content=ft.Text(f"✓ Entrada de {entrada.cantidad} {producto_nombre} eliminada. Stock revertido."),
                    bgcolor=ft.Colors.GREEN_700
                )
                self.page.overlay.append(snack)
                snack.open = True
                self.page.update()
                
                self._load_entradas_pendientes()
                
            except Exception as ex:
                db.rollback()
                logger.error(f"Error eliminando entrada: {ex}")
                snack_err = ft.SnackBar(content=ft.Text(f"❌ Error: {str(ex)[:50]}"), bgcolor=ft.Colors.RED_700)
                self.page.overlay.append(snack_err)
                snack_err.open = True
                self.page.update()
            finally:
                db.close()
        
        dialog = ft.AlertDialog(
            title=ft.Text("Eliminar Entrada"),
            content=ft.Column([
                ft.Text(f"¿Eliminar la entrada de {entrada.cantidad} {producto_nombre}?"),
                ft.Container(height=5),
                ft.Text(
                    "Esta acción revertirá el stock. Si había 0 unidades y se agregaron "
                    f"{entrada.cantidad}, volverán a quedar en 0.",
                    size=12, color=ft.Colors.ORANGE_700
                ),
            ], tight=True),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Eliminar", bgcolor=ft.Colors.RED_600, color="white", on_click=on_confirmar),
            ],
        )
        
        self.active_dialog = dialog
        self.page.overlay.append(dialog)
        dialog.open = True
        self.page.update()

    def _show_validar_dialog(self, e):
        factura_input = ft.TextField(
            label="Número de Factura", 
            border_radius=10, 
            autofocus=True,
            hint_text="Ej: FAC-2024-001"
        )
        
        def on_confirmar(ev):
            self.active_dialog.open = False
            self.page.update()
            self._process_validation(factura_input.value)

        self.active_dialog = ft.AlertDialog(
            title=ft.Text("Validar Entradas"),
            content=ft.Column([
                ft.Text(f"Se vincularán {len(self.selected_entradas)} entradas seleccionadas."),
                factura_input
            ], tight=True, spacing=15),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton(
                    "Validar ahora", 
                    bgcolor=ft.Colors.BLUE_600, 
                    color="white", 
                    on_click=on_confirmar
                )
            ]
        )
        
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _process_validation(self, ref_factura):
        db = next(get_db())
        try:
            nueva_fac = Factura(
                numero_factura=ref_factura if ref_factura else f"V-REF-{datetime.now().strftime('%H%M%S')}",
                proveedor="Varios",
                fecha_factura=datetime.now(),
                fecha_recepcion=datetime.now(),
                total_bruto=0, total_impuestos=0, total_neto=0,
                estado="Validada",
                validada_por="Admin",
                fecha_validacion=datetime.now()
            )
            db.add(nueva_fac)
            db.flush()

            movimientos = db.query(Movimiento).filter(Movimiento.id.in_(list(self.selected_entradas))).all()
            for m in movimientos:
                m.factura_id = nueva_fac.id
            
            db.commit()
            self.selected_entradas.clear()
            self._load_entradas_pendientes()
            
            snack = ft.SnackBar(content=ft.Text("✅ Entradas validadas correctamente"), bgcolor=ft.Colors.GREEN_700)
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()

        except Exception as ex:
            db.rollback()
            logger.error(f"Error procesando validación: {ex}")
            snack_err = ft.SnackBar(content=ft.Text(f"❌ Error: {str(ex)[:50]}"), bgcolor=ft.Colors.RED_700)
            self.page.overlay.append(snack_err)
            snack_err.open = True
            self.page.update()
        finally:
            db.close()

    def _close_dialog(self, e=None):
        if hasattr(self, 'active_dialog') and self.active_dialog:
            self.active_dialog.open = False
            self.page.update()