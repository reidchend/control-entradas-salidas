import flet as ft
from datetime import datetime


class ValidacionFields:
    def __init__(self, page, theme_colors):
        self.page = page
        self.theme_colors = theme_colors
        self._build_fields()
    
    def _build_fields(self):
        self.factura_input = ft.TextField(
            label="Número de Factura",
            border_radius=10,
            autofocus=True,
            hint_text="Ej: FAC-2024-001",
            expand=True
        )
        
        from usr.database.local_replica import LocalReplica
        proveedores = LocalReplica.get_proveedores(estado="Activo")
        proveedor_opts = [ft.dropdown.Option(p['nombre'], p['nombre']) for p in proveedores]
        proveedor_opts.append(ft.dropdown.Option("__nuevo__", "+ Agregar nuevo"))
        
        self.proveedor_dd = ft.Dropdown(
            label="Proveedor",
            options=proveedor_opts,
            border_radius=10,
            expand=True,
            on_change=self._on_proveedor_change
        )
        
        self.nuevo_proveedor_rif = ft.TextField(
            label="Nuevo RIF",
            prefix_icon=ft.Icons.BADGE,
            border_radius=10,
            width=150,
            visible=False,
            hint_text="J-XXXXXXXX-X"
        )
        
        self.nuevo_proveedor_input = ft.TextField(
            label="Nuevo Proveedor",
            border_radius=10,
            expand=True,
            visible=False
        )
        
        self.monto_total_input = ft.TextField(
            label="Monto Total (VES)",
            prefix_icon=ft.Icons.ATTACH_MONEY,
            border_radius=10,
            hint_text="1000.00",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True,
            on_change=self._on_monto_change
        )
        
        self.fecha_picker = ft.DatePicker(
            first_date=datetime(2020, 1, 1),
            last_date=datetime.now(),
            value=datetime.now()
        )
        
        self.fecha_label = ft.Text(
            f"Fecha: {datetime.now().strftime('%d/%m/%Y')}",
            size=12,
            color=self.theme_colors.get('text_secondary')
        )
        
        self.fecha_btn = ft.ElevatedButton(
            "📅 Fecha",
            on_click=lambda _: self.page.open(self.fecha_picker)
        )
        
        self.fecha_picker.on_change = lambda e: self._on_fecha_change(e)
        
        self.validar_btn = ft.ElevatedButton(
            "✓ Validar Entradas",
            bgcolor=self.theme_colors.get('success', '#4CAF50'),
            color="white",
            disabled=True,
            height=45
        )
    
    def _on_proveedor_change(self, e):
        is_nuevo = self.proveedor_dd.value == "__nuevo__"
        self.nuevo_proveedor_input.visible = is_nuevo
        self.nuevo_proveedor_rif.visible = is_nuevo
        self.page.update()
    
    def _on_monto_change(self, e):
        pass
    
    def _on_fecha_change(self, e):
        self.fecha_label.value = f"Fecha: {self.fecha_picker.value.strftime('%d/%m/%Y')}"
        self.page.update()
    
    def section_container(self, content_col):
        return ft.Container(
            content=content_col,
            padding=15,
            border_radius=12,
            border=ft.border.all(1, self.theme_colors.get('border', '#333333')),
            bgcolor=self.theme_colors.get('surface', '#252525')
        )
    
    def get_doc_section(self):
        return self.section_container(ft.Column([
            ft.Row([ft.Icon(ft.Icons.RECEIPT_LONG), ft.Text("📋 Datos del Documento", weight="bold", size=14)]),
            ft.Row([self.factura_input], spacing=10),
            ft.Row([self.proveedor_dd]),
            ft.Row([self.nuevo_proveedor_input, self.nuevo_proveedor_rif], spacing=10),
            ft.Row([self.fecha_btn, self.fecha_label], spacing=10),
        ], spacing=10))
    
    def get_monto_section(self):
        return self.section_container(ft.Column([
            ft.Row([ft.Icon(ft.Icons.ATTACH_MONEY), ft.Text("💰 Monto Total", weight="bold", size=14)]),
            self.monto_total_input,
        ], spacing=10))
    
    def get_validar_btn(self):
        return self.validar_btn
    
    def get_data(self):
        rif = ""
        if self.proveedor_dd.value == "__nuevo__":
            prov = self.nuevo_proveedor_input.value or "Varios"
            rif = self.nuevo_proveedor_rif.value or ""
        else:
            prov = self.proveedor_dd.value or "Varios"
        
        try:
            monto = float(self.monto_total_input.value) if self.monto_total_input.value else 0
        except:
            monto = 0
        
        fecha = self.fecha_picker.value if self.fecha_picker.value else datetime.now()
        
        return {
            'proveedor': prov,
            'rif': rif,
            'factura': self.factura_input.value or "",
            'monto': monto,
            'fecha': fecha
        }