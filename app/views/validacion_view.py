import flet as ft
from datetime import datetime
from app.database.base import get_db
from app.models import Movimiento, Factura, Producto, Categoria

class ValidacionView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.bgcolor = ft.Colors.GREY_50
        self.padding = 0
        
        # Componentes UI
        self.entradas_list = ft.ListView(
            expand=True,
            spacing=10,
            padding=ft.padding.only(left=15, right=15, bottom=20),
        )
        self.search_field = None
        self.validate_button = None
        self.clear_button = None
        
        # Estado
        self.selected_entradas = set()
        self.entradas_data = {}
        
        self._build_ui()
    
    def update_view(self):
        """Refrescar datos (Llamar desde main.py al cambiar a esta pestaña)"""
        self._load_entradas_pendientes()

    def did_mount(self):
        """Carga inicial al montar el componente"""
        self._load_entradas_pendientes()
    
    def _build_ui(self):
        # --- HEADER ---
        header = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Column([
                        ft.Text("Validación", size=26, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_GREY_900),
                        ft.Text("Vincular entradas a facturas", size=13, color=ft.Colors.BLUE_GREY_400),
                    ], expand=True, spacing=0),
                    ft.IconButton(
                        icon=ft.Icons.REFRESH_ROUNDED,
                        icon_color=ft.Colors.BLUE_600,
                        on_click=lambda _: self._load_entradas_pendientes(),
                        tooltip="Refrescar lista"
                    )
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            ], spacing=2),
            padding=ft.padding.only(left=20, top=20, right=20, bottom=10)
        )

        # --- FILTROS Y ACCIONES ---
        self.search_field = ft.TextField(
            hint_text="Buscar producto...",
            prefix_icon=ft.Icons.SEARCH_ROUNDED,
            border_radius=12,
            bgcolor=ft.Colors.WHITE,
            border_color=ft.Colors.TRANSPARENT,
            height=45,
            text_size=14,
            content_padding=ft.padding.symmetric(horizontal=15),
            on_change=self._filter_entradas,
        )

        self.validate_button = ft.ElevatedButton(
            text="Validar (0)",
            icon=ft.Icons.FACT_CHECK_ROUNDED,
            color="white",
            bgcolor=ft.Colors.BLUE_600,
            disabled=True,
            style=ft.ButtonStyle(shape=ft.RoundedRectangleBorder(radius=10)),
            on_click=self._show_validar_dialog,
        )
        
        self.clear_button = ft.TextButton(
            text="Limpiar",
            icon=ft.Icons.CLOSE_ROUNDED,
            style=ft.ButtonStyle(color=ft.Colors.BLUE_GREY_400),
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

        # --- ENSAMBLADO FINAL ---
        # Usamos un Column con expand=True para que el ListView ocupe el resto del espacio
        self.content = ft.Column([
            header,
            controls_section,
            self.entradas_list # ListView ya tiene expand=True
        ], spacing=0, expand=True)

    def _create_entrada_card(self, entrada: Movimiento):
        is_selected = entrada.id in self.selected_entradas
        bg_color = ft.Colors.BLUE_50 if is_selected else ft.Colors.WHITE
        border_side = ft.border.BorderSide(2, ft.Colors.BLUE_600) if is_selected else ft.border.BorderSide(1, ft.Colors.GREY_200)
        
        return ft.Container(
            content=ft.Row([
                ft.Container(
                    content=ft.Icon(
                        ft.Icons.CHECK_CIRCLE_ROUNDED if is_selected else ft.Icons.RADIO_BUTTON_UNCHECKED_ROUNDED,
                        color=ft.Colors.BLUE_600 if is_selected else ft.Colors.GREY_300,
                        size=22
                    ),
                    padding=2
                ),
                ft.Column([
                    ft.Text(
                        entrada.producto.nombre if entrada.producto else "Cargando...",
                        weight=ft.FontWeight.BOLD, size=15, color=ft.Colors.BLUE_GREY_900,
                        max_lines=1, overflow=ft.TextOverflow.ELLIPSIS
                    ),
                    ft.Row([
                        ft.Text(f"{entrada.cantidad} {entrada.producto.unidad_medida if entrada.producto else ''}", 
                                size=13, weight="w600", color=ft.Colors.BLUE_700),
                        ft.Text(" • ", color=ft.Colors.GREY_300),
                        ft.Text(entrada.fecha_movimiento.strftime("%d/%m %H:%M"), size=12, color=ft.Colors.BLUE_GREY_400),
                    ], spacing=2)
                ], expand=True, spacing=2)
            ], spacing=12),
            padding=15,
            bgcolor=bg_color,
            border_radius=12,
            border=ft.border.all(border_side.width, border_side.color),
            on_click=lambda _: self._toggle_entrada_selection(entrada.id)
        )

    def _load_entradas_pendientes(self):
        try:
            db = next(get_db())
            # Consulta idéntica a la funcional original: tipo entrada y factura_id nulo
            query = db.query(Movimiento).filter(
                Movimiento.tipo == "entrada",
                Movimiento.factura_id.is_(None)
            )
            
            search_term = self.search_field.value.lower().strip() if self.search_field and self.search_field.value else ""
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
                        alignment=ft.alignment.center
                    )
                )
            else:
                for ent in entradas:
                    self.entradas_list.controls.append(self._create_entrada_card(ent))
            
            self._update_validate_button_state()
            self.update()
        except Exception as ex:
            print(f"Error en ValidacionView: {ex}")
        finally:
            db.close()

    def _toggle_entrada_selection(self, eid):
        if eid in self.selected_entradas:
            self.selected_entradas.remove(eid)
        else:
            self.selected_entradas.add(eid)
        
        # Actualización visual rápida
        self.entradas_list.controls.clear()
        for entrada in self.entradas_data.values():
            self.entradas_list.controls.append(self._create_entrada_card(entrada))
        
        self._update_validate_button_state()
        self.update()

    def _update_validate_button_state(self):
        count = len(self.selected_entradas)
        self.validate_button.text = f"Validar ({count})"
        self.validate_button.disabled = count == 0
        self.clear_button.visible = count > 0

    def _clear_selection(self, e):
        self.selected_entradas.clear()
        self._load_entradas_pendientes()

    def _filter_entradas(self, e):
        self._load_entradas_pendientes()

    def _show_validar_dialog(self, e):
        factura_input = ft.TextField(
            label="Número de Factura", 
            border_radius=10, 
            autofocus=True,
            hint_text="Ej: FAC-2024-001"
        )
        
        def on_confirmar(ev):
            # Cerramos el diálogo antes de procesar
            self.active_dialog.open = False
            self.page.update()
            self._process_validation(factura_input.value)

        # Creamos el diálogo como una variable de la clase
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
        
        # Agregamos al overlay y abrimos
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _process_validation(self, ref_factura):
        """Procesa la vinculación de entradas a una factura."""
        db = next(get_db())
        try:
            # 1. Crear la factura de respaldo
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

            # 2. Vincular los movimientos seleccionados
            movimientos = db.query(Movimiento).filter(Movimiento.id.in_(list(self.selected_entradas))).all()
            for m in movimientos:
                m.factura_id = nueva_fac.id
            
            db.commit()
            
            # 3. Limpiar estado y notificar
            self.selected_entradas.clear()
            self._load_entradas_pendientes()
            
            snack = ft.SnackBar(
                content=ft.Text("✅ Entradas validadas correctamente"),
                bgcolor=ft.Colors.GREEN_700
            )
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()

        except Exception as ex:
            db.rollback()
            logger.error(f"Error procesando validación: {ex}")
            # Notificación de error
            snack_err = ft.SnackBar(
                content=ft.Text(f"❌ Error: {str(ex)[:50]}"),
                bgcolor=ft.Colors.RED_700
            )
            self.page.overlay.append(snack_err)
            snack_err.open = True
            self.page.update()

        finally:
            db.close()

    def _close_dialog(self, e=None):
        """Cierra el diálogo de forma segura."""
        if hasattr(self, 'active_dialog') and self.active_dialog:
            self.active_dialog.open = False
            self.page.update()
            # Limpiamos el overlay para evitar acumular objetos
            if self.active_dialog in self.page.overlay:
                self.page.overlay.remove(self.active_dialog)
                self.page.update()