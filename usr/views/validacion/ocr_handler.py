import flet as ft
import os


class OCRHandler:
    def __init__(self, page, theme_colors, fields=None):
        self.page = page
        self.theme_colors = theme_colors
        self.fields = fields
        
        self._build_ui()
    
    def _build_ui(self):
        self.image_preview = ft.Container(
            content=ft.Text("Sin imagen", size=12, color=self.theme_colors.get('text_hint')),
            width=200, height=100,
            bgcolor=self.theme_colors.get('surface'),
            border_radius=8, visible=False
        )
        
        self.result_text = ft.TextField(
            "", read_only=True, border_color=ft.Colors.TRANSPARENT,
            text_size=12, color=self.theme_colors.get('success')
        )
        
        self.status_text = ft.TextField(
            "", read_only=True, border_color=ft.Colors.TRANSPARENT, text_size=11
        )
        
        self.btn_pegar = ft.ElevatedButton(
            "📋 Pegar Imagen",
            icon=ft.Icons.CONTENT_PASTE,
            on_click=self._on_paste_click
        )
        
        self.btn_seleccionar = ft.ElevatedButton(
            "📂 Seleccionar",
            icon=ft.Icons.FOLDER_OPEN,
            on_click=self._on_select_click
        )
        
        self.file_picker = ft.FilePicker()
    
    def section_container(self, content_col):
        return ft.Container(
            content=content_col,
            padding=15,
            border_radius=12,
            border=ft.border.all(1, self.theme_colors.get('border', '#333333')),
            bgcolor=self.theme_colors.get('surface', '#252525')
        )
    
    def get_ui(self):
        return self.section_container(ft.Column([
            ft.Row([ft.Icon(ft.Icons.CAMERA_ALT), ft.Text("📷 Extraer de Imagen", weight="bold", size=14)]),
            ft.Row([self.btn_pegar, self.btn_seleccionar], spacing=10),
            ft.Container(content=self.image_preview, alignment=ft.alignment.center),
            ft.Container(content=self.result_text, padding=ft.padding.only(top=5)),
            ft.Container(content=self.status_text, padding=ft.padding.only(top=5)),
        ], spacing=10))
    
    def _on_paste_click(self, e):
        self.status_text.value = "⏳ Intentando portapapeles..."
        self.page.update()
    
    def _on_select_click(self, e):
        self.file_picker.pick_files(allowed_extensions=["png", "jpg", "jpeg", "bmp", "webp"])
    
    def _on_file_select(self, e):
        if not e.files:
            self.status_text.value = "❌ Sin archivos"
            self.status_text.color = self.theme_colors.get('error')
            self.page.update()
            return
        
        f = e.files[0]
        image_path = getattr(f, 'path', None)
        
        if not image_path:
            self.status_text.value = "❌ Archivo sin ruta local"
            self.status_text.color = self.theme_colors.get('error')
            self.page.update()
            return
        
        self._process_image(image_path)
    
    def _process_image(self, image_path):
        if not image_path or not os.path.exists(image_path):
            self.status_text.value = "❌ Ruta inválida"
            self.status_text.color = self.theme_colors.get('error')
            self.page.update()
            return
        
        self.image_preview.visible = True
        self.image_preview.content = ft.Image(src=image_path, width=200, height=100, fit="contain")
        
        try:
            from usr.ocr_extractor import extract_from_image, check_proveedor_exists
            datos = extract_from_image(image_path)
            
            resultado = f"Proveedor: {datos.get('proveedor', 'N/A')}\n"
            resultado += f"RIF: {datos.get('rif', 'N/A')}\n"
            resultado += f"Factura: {datos.get('nro_factura', 'N/A')}\n"
            resultado += f"Fecha: {datos.get('fecha', 'N/A')}"
            self.result_text.value = resultado
            
            if self.fields:
                if datos.get('nro_factura'):
                    self.fields.factura_input.value = datos['nro_factura']
                
                if datos.get('proveedor'):
                    prov = check_proveedor_exists(datos['proveedor'], datos.get('rif', ''))
                    if prov['existe']:
                        self.fields.proveedor_dd.value = prov['nombre']
                        self.status_text.value = f"Proveedor: {prov['nombre']}"
                    else:
                        self.fields.proveedor_dd.value = "__nuevo__"
                        self.fields.nuevo_proveedor_input.visible = True
                        self.fields.nuevo_proveedor_input.value = datos['proveedor']
                        self.fields.nuevo_proveedor_rif.visible = True
                        self.fields.nuevo_proveedor_rif.value = datos.get('rif', '')
                        self.status_text.value = "Nuevo proveedor"
            
            self.status_text.value = "✅ Datos extraídos"
            self.status_text.color = self.theme_colors.get('success')
        except Exception as ex:
            self.status_text.value = f"Error: {str(ex)}"
            self.status_text.color = self.theme_colors.get('error')
        
        self.page.update()