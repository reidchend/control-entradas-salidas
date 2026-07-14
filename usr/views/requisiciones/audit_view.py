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
        # Simple modal for stock adjustment
        qty_input = ft.TextField(
            label="Cantidad Física Real", 
            value=str(item['origen']['inicial']),
            keyboard_type=ft.KeyboardType.NUMBER,
            width=200
        )
        
        def accept_adjust(_):
            try:
                nueva_qty = float(qty_input.value)
                if crear_ajuste_stock(item['producto_id'], self.audit_data['requisicion'].origen, nueva_qty, "Ajuste durante auditoría"):
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
                ft.Text(f"Cantidad actual: {item['origen']['inicial']:.2f}"),
                qty_input,
            ], tight=True),
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
        # Since it's already in DB (verified status), we just notify

    def _on_totalizar(self, _):
        # Check if all verified
        unverified = [i['ingrediente'] for i in self.audit_data['items'] if not i['verificado']]
        if unverified:
            show_warning(f"Hay productos no verificados: {', '.join(unverified[:3])}...")
            return
            
        try:
            if totalizar_requisicion(self.req_id):
                show_success("Requisición totalizada y stock trasladado")
                self.on_back()
        except Exception as e:
            show_error(f"Error al totalizar: {e}")
