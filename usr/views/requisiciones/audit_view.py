import flet as ft
from datetime import datetime
from usr.theme import get_colors
from usr.views.requisiciones.helpers import _colors, _c
from usr.views.requisiciones.data import (
    get_requisicion_audit_data, 
    marcar_detalle_verificado, 
    crear_ajuste_stock, 
    totalizar_requisicion
)
from usr.notifications import show_success, show_error, show_warning

def _forzar_sync():
    try:
        from usr.database.sync import get_sync_manager
        sync_mgr = get_sync_manager()
        if sync_mgr and sync_mgr.check_connection():
            import threading
            thread = threading.Thread(target=sync_mgr.full_sync, daemon=True)
            thread.start()
    except Exception as e:
        print(f"[AUDIT] Error al forzar sync: {e}")

class AuditView(ft.Container):
    def __init__(self, req_id, on_back):
        super().__init__()
        self.req_id = req_id
        self.on_back = on_back
        self.expand = True
        self.padding = 20
        self.audit_data = None
        self._build_ui()

    def _build_ui(self):
        self.colors = _colors(self.page)
        
    def _build_ui(self):
        self.colors = _colors(self.page)
        
        # Header - Rediseñado para evitar desbordamiento en móvil
        self.header = ft.Column([
            ft.Row([
                ft.IconButton(
                    ft.Icons.ARROW_BACK_IOS_NEW_ROUNDED, 
                    on_click=lambda _: self.on_back(), 
                    icon_color=self.colors['text_primary']
                ),
                ft.Column([
                    ft.Text("Auditoría de Requisición", size=20, weight="bold", color=self.colors['text_primary'], max_lines=1, overflow=ft.TextOverflow.ELLIPSIS),
                    ft.Text("Verifique stock físico antes de totalizar", size=12, color=self.colors['text_secondary'], max_lines=1, overflow=ft.TextOverflow.ELLIPSIS),
                ], expand=True, spacing=0),
            ], alignment=ft.MainAxisAlignment.START),
            ft.Row([
                ft.ElevatedButton("Guardar", icon=ft.Icons.SAVE, on_click=self._on_guardar, 
                                   style=ft.ButtonStyle(color=self.colors['text_primary'], bgcolor=self.colors['surface'])),
                ft.ElevatedButton("Totalizar", icon=ft.Icons.CHECK_CIRCLE, on_click=self._on_totalizar,
                                   style=ft.ButtonStyle(color=self.colors['white'], bgcolor=self.colors['success'])),
            ], alignment=ft.MainAxisAlignment.END, spacing=10),
        ], spacing=10)

        # Tabs


        # Tabs
        self.tabs = ft.Tabs(
            selected_index=0,
            on_change=self._on_tab_change,
            tabs=[
                ft.Tab(text="Salida (Origen)", icon=ft.Icons.OUTBOX),
                ft.Tab(text="Destino", icon=ft.Icons.INBOX),
            ],
            expand=False,
        )

        # Content Area
        self.content_area = ft.Column(
            expand=True, 
            scroll=ft.ScrollMode.AUTO
        )
        
        self.content = ft.Column([
            self.header,
            ft.Divider(height=1, color=self.colors['border']),
            self.tabs,
            self.content_area,
        ], expand=True, spacing=10)
        
        self.bgcolor = self.colors['bg']
        self._load_data()

    def _load_data(self):
        self.audit_data = get_requisicion_audit_data(self.req_id)
        if not self.audit_data:
            self.content_area.content = ft.Text("Error cargando datos de auditoría", color=self.colors['error'])
            return
        self._update_tab_content()

    def _on_tab_change(self, e):
        self._update_tab_content()

    def _update_tab_content(self):
        if not self.audit_data: return
        
        index = self.tabs.selected_index
        tab_key = 'origen' if index == 0 else 'destino'
        
        # 1. Definir la cabecera (sin envolver en Row aquí, lo haremos al final)
        header_row = ft.Row([
            ft.Text("✓", width=30, weight="bold", color=self.colors['text_secondary']),
            ft.Text("Producto", width=150, weight="bold", color=self.colors['text_secondary']),
            ft.Text("Inicial", width=80, text_align=ft.TextAlign.RIGHT, weight="bold", color=self.colors['text_secondary']),
            ft.Text("Traslado", width=80, text_align=ft.TextAlign.RIGHT, weight="bold", color=self.colors['text_secondary']),
            ft.Text("Final", width=80, text_align=ft.TextAlign.RIGHT, weight="bold", color=self.colors['text_secondary']),
        ], spacing=10)

        # 2. Crear las filas
        rows = []
        for item in self.audit_data['items']:
            data = item[tab_key]
            
            adj_btn = None
            if tab_key == 'origen':
                adj_btn = ft.IconButton(
                    ft.Icons.EDIT_NOTE, 
                    icon_size=16, 
                    icon_color=self.colors['accent'],
                    on_click=lambda e, i=item: self._show_adjust_dialog(i)
                )
            
            row = ft.Container(
                content=ft.Row([
                    ft.Checkbox(
                        value=item['verificado'], 
                        on_change=lambda e, id=item['detalle_id']: self._on_verify(id, e.control.value),
                        fill_color=self.colors['accent']
                    ),
                    ft.Text(item['ingrediente'], width=150, color=self.colors['text_primary'], overflow=ft.TextOverflow.ELLIPSIS),
                    ft.Row([
                        ft.Text(f"{data['inicial']:.2f}", width=60, text_align=ft.TextAlign.RIGHT),
                        adj_btn if adj_btn else ft.Container(width=30),
                    ], spacing=5),
                    ft.Text(f"{data['trasladada']:.2f}", width=80, text_align=ft.TextAlign.RIGHT, color=self.colors['accent']),
                    ft.Text(f"{data['final']:.2f}", width=80, text_align=ft.TextAlign.RIGHT, weight="bold"),
                ], spacing=10),
                padding=10,
                bgcolor=self.colors['card'] if item['verificado'] else self.colors['bg'],
                border_radius=8,
                border=ft.border.all(1, self.colors['border']),
            )
            rows.append(row)

        # 3. Envolver TODO en un solo contenedor con scroll horizontal
        table_column = ft.Column([
            header_row,
            ft.Column(rows, spacing=5),
        ], spacing=10, width=550)

        self.content_area.controls = [
            ft.Row([
                table_column
            ], scroll=ft.ScrollMode.ALWAYS)
        ]
        
        if self.page:
            self.update()


    def _on_verify(self, detalle_id, value):
        marcar_detalle_verificado(detalle_id, value)
        # Update local data cache
        for item in self.audit_data['items']:
            if item['detalle_id'] == detalle_id:
                item['verificado'] = value
                break
        self._update_tab_content()

    def _show_adjust_dialog(self, item):
        # Verificar si el producto es pesable
        es_pesable = False
        try:
            from usr.models import Producto
            from usr.database.base import get_db_adaptive
            db = next(get_db_adaptive())
            try:
                prod = db.query(Producto).filter(Producto.id == item['producto_id']).first()
                es_pesable = prod.es_pesable if prod else False
            finally:
                db.close()
        except Exception:
            pass

        colors = _colors(self.page)
        current_qty = item['origen']['inicial']
        trasladada = item['origen']['trasladada']
        final_actual = current_qty - trasladada

        if es_pesable:
            # --- Calculadora para productos pesables ---
            def _recalc_desde_peso_total():
                """Actualiza Final cuando cambia Peso Total (Inicial)."""
                try:
                    pt = float(peso_total_input.value.replace(',', '.'))
                    final_input.value = f"{pt - trasladada:.3f}"
                    final_input.update()
                except Exception:
                    pass

            def _calcular_desde_unidades(e):
                try:
                    cant = float(cant_x_unidad_input.value or 0)
                    pu = float((peso_x_unidad_input.value or "0").replace(',', '.'))
                    peso_total_input.value = f"{cant * pu:.3f}"
                    peso_total_input.update()
                    _recalc_desde_peso_total()
                except Exception:
                    peso_total_input.value = "0.000"
                    peso_total_input.update()
                    _recalc_desde_peso_total()

            def _calcular_desde_total(e):
                try:
                    total = float((peso_total_input.value or "0").replace(',', '.'))
                    cant = float(cant_x_unidad_input.value or 1)
                    if cant > 0:
                        peso_x_unidad_input.value = f"{total / cant:.3f}"
                        peso_x_unidad_input.update()
                    _recalc_desde_peso_total()
                except Exception:
                    pass

            def _on_final_change(e):
                """Cuando el usuario edita Final, recalcula Peso Total (Inicial)."""
                try:
                    nuevo_final = float(final_input.value.replace(',', '.'))
                    nuevo_inicial = nuevo_final + trasladada
                    peso_total_input.value = f"{nuevo_inicial:.3f}"
                    peso_total_input.update()
                    # Actualizar calculadora inversa
                    cant_u = float(cant_x_unidad_input.value or 1)
                    if cant_u > 0:
                        peso_x_unidad_input.value = f"{nuevo_inicial / cant_u:.3f}"
                        peso_x_unidad_input.update()
                except Exception:
                    pass

            cant_x_unidad_input = ft.TextField(
                label="Und.", value="1", keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10, text_size=14, expand=1,
                on_change=_calcular_desde_unidades,
            )
            peso_x_unidad_input = ft.TextField(
                label="Kg/unidad", value="0.100", keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10, text_size=14, expand=1,
                on_change=_calcular_desde_unidades,
            )
            peso_total_input = ft.TextField(
                label="Peso Inicial", value=f"{current_qty:.3f}", keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10, text_size=14, expand=1,
                suffix_text="kg", on_change=_calcular_desde_total,
            )
            final_input = ft.TextField(
                label="Stock Final", value=f"{final_actual:.3f}", keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10, text_size=14, expand=1,
                suffix_text="kg", on_change=_on_final_change,
            )

            campos = ft.Column([
                ft.Text(f"Trasladada: {trasladada:.3f} kg", size=13, color=colors['text_secondary']),
                ft.Row([cant_x_unidad_input, peso_x_unidad_input], spacing=8),
                ft.Row([peso_total_input, final_input], spacing=8),
            ], spacing=8, tight=True)

            def accept_adjust(_):
                try:
                    peso_total = float(peso_total_input.value.replace(',', '.'))
                    if peso_total <= 0:
                        show_warning("El peso debe ser mayor a 0")
                        return
                    if crear_ajuste_stock(item['producto_id'], self.audit_data['requisicion'].origen,
                                          peso_total, "Ajuste durante auditoría", peso_total=peso_total):
                        show_success("Stock ajustado correctamente")
                        self._load_data()
                        dlg.open = False
                        self.page.update()
                    else:
                        show_error("Error al aplicar ajuste")
                except ValueError:
                    show_warning("Ingrese un peso válido")
        else:
            # --- Campos simples para no pesables ---
            def _on_inicial_change(e):
                try:
                    inic = float(inicial_input.value)
                    final_input.value = f"{inic - trasladada:.0f}"
                    final_input.update()
                except Exception:
                    pass

            def _on_final_change(e):
                try:
                    fin = float(final_input.value)
                    nuevo_inicial = fin + trasladada
                    inicial_input.value = f"{nuevo_inicial:.0f}"
                    inicial_input.update()
                except Exception:
                    pass

            inicial_input = ft.TextField(
                label="Stock Inicial", value=str(int(current_qty)),
                keyboard_type=ft.KeyboardType.NUMBER, expand=1,
                border_radius=10, text_size=14, on_change=_on_inicial_change,
            )
            final_input = ft.TextField(
                label="Stock Final", value=str(int(final_actual)),
                keyboard_type=ft.KeyboardType.NUMBER, expand=1,
                border_radius=10, text_size=14, on_change=_on_final_change,
            )

            campos = ft.Column([
                ft.Text(f"Cantidad a trasladar: {int(trasladada)}", size=13, color=colors['text_secondary']),
                ft.Row([inicial_input, final_input], spacing=10),
            ], spacing=8, tight=True)

            def accept_adjust(_):
                try:
                    nueva_qty = float(inicial_input.value)
                    if nueva_qty < 0:
                        show_warning("La cantidad no puede ser negativa")
                        return
                    if crear_ajuste_stock(item['producto_id'], self.audit_data['requisicion'].origen,
                                          nueva_qty, "Ajuste durante auditoría"):
                        show_success("Stock ajustado correctamente")
                        self._load_data()
                        dlg.open = False
                        self.page.update()
                    else:
                        show_error("Error al aplicar ajuste")
                except ValueError:
                    show_warning("Ingrese una cantidad válida")

        dlg = ft.AlertDialog(
            title=ft.Text(f"Ajustar {item['ingrediente']}"),
            content=ft.Column([
                ft.Text(f"Stock actual: {current_qty:.2f}", size=14),
                ft.Container(height=10),
                campos,
            ], tight=True, spacing=8),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog(dlg)),
                ft.ElevatedButton("Aceptar", on_click=accept_adjust),
            ]
        )
        self.page.overlay.append(dlg)
        dlg.open = True
        self.page.update()

    def _close_dialog(self, dlg):
        dlg.open = False
        self.page.update()

    def _on_guardar(self, _):
        show_success("Progreso de auditoría guardado")
        _forzar_sync()

    def _on_totalizar(self, _):
        # Check if all verified
        unverified = [i['ingrediente'] for i in self.audit_data['items'] if not i['verificado']]
        if unverified:
            show_warning(f"Hay productos no verificados: {', '.join(unverified[:3])}...")
            return
            
        try:
            if totalizar_requisicion(self.req_id):
                show_success("Requisición totalizada y stock trasladado")
                _forzar_sync()
                self.on_back()
        except Exception as e:
            show_error(f"Error al totalizar: {e}")
