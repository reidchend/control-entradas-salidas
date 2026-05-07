import flet as ft
from datetime import datetime
from .ocr_handler import OCRHandler
from .fields import ValidacionFields
from .payments import PaymentsManager


class ValidacionDialog:
    def __init__(self, page, selected_entradas, theme_colors):
        self.page = page
        self.selected_entradas = selected_entradas
        self.theme_colors = theme_colors
        
        self.is_mobile = page.width < 600 if page else False
        self.fields = ValidacionFields(page, theme_colors)
        self.ocr = OCRHandler(page, theme_colors, self.fields)
        self.payments = PaymentsManager(theme_colors)
        
        self._build_ui()
    
    def _build_ui(self):
        from usr.database.local_replica import LocalReplica
        
        usuario = LocalReplica.get_usuario_dispositivo()
        nombre_usuario = usuario['nombre'] if usuario else "Sistema"
        
        dialog_width = 400 if self.is_mobile else 650
        
        usuario_label = ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.PERSON, size=18, color=self.theme_colors.get('accent', '#BB86FC')),
                ft.Text(f"Validado por: {nombre_usuario}", weight="bold", size=13, color=self.theme_colors.get('text_primary'))
            ]),
            padding=ft.padding.symmetric(horizontal=12, vertical=8),
            bgcolor=self.theme_colors.get('accent_dark', '#9A67EA'),
            border_radius=8
        )
        
        content = ft.Column([
            usuario_label,
            ft.Divider(height=1),
            ft.Text(f"Se validarán {len(self.selected_entradas)} entrada(s)", weight="bold", size=14),
            ft.Container(height=5),
            self.ocr.get_ui(),
            ft.Container(height=10),
            self.fields.get_doc_section(),
            ft.Container(height=10),
            self.fields.get_monto_section(),
            ft.Container(height=10),
            self.payments.get_ui(),
            ft.Container(height=10),
            self.payments.get_resumen(),
            ft.Container(height=5),
            self.fields.get_validar_btn(),
        ], spacing=0, scroll=ft.ScrollMode.AUTO)
        
        self.dialog = ft.AlertDialog(
            title=ft.Text("✅ Validar Entradas"),
            content=ft.Container(width=dialog_width, content=content, padding=20),
            actions=[ft.TextButton("Cancelar", on_click=self._on_cancel)],
            actions_alignment=ft.MainAxisAlignment.END
        )
    
    def _on_cancel(self, e):
        self.dialog.open = False
        self.page.update()
    
    def _on_validar(self, e):
        data = self.get_data()
        if self.fields.validar_btn.disabled:
            return
        self.dialog.open = False
        self.page.update()
        return data
    
    def get_data(self):
        return self.fields.get_data() | {'pagos': self.payments.get_pagos()}
    
    def set_on_validate(self, callback):
        self.fields.validar_btn.on_click = callback
    
    def show(self):
        # Setup file picker callback
        self.ocr.file_picker.on_change = self.ocr._on_file_select
        self.page.overlay.append(self.dialog)
        self.page.overlay.append(self.ocr.file_picker)
        self.dialog.open = True
        self.page.update()
    
    @property
    def validar_btn(self):
        return self.fields.validar_btn
    
    @property
    def faltante_ves(self):
        return self.payments.faltante_ves