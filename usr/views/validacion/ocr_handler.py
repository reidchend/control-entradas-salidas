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
            text_size=12, color=self.theme_colors.get('success'))
        
        self.status_text = ft.TextField(
            "", read_only=True, border_color=ft.Colors.TRANSPARENT, text_size=11)
        
        # Manual path input as fallback
        self.path_input = ft.TextField(
            label="Ruta de imagen",
            hint_text="/ruta/a/imagen.jpg",
            expand=True,
            on_submit=self._on_path_submit
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
        
        self.btn_path_load = ft.ElevatedButton(
            "📂 Cargar Ruta",
            icon=ft.Icons.UPLOAD_FILE,
            on_click=self._on_path_load_click
        )
        
        self.file_picker = ft.FilePicker(on_result=self._on_file_select)
    
    def section_container(self, content_col):
        return ft.Container(
            content=content_col,
            padding=15,
            border_radius=12,
            border=ft.border.all(1, self.theme_colors.get('border', '#333333')),
            bgcolor=self.theme_colors.get('surface', '#252525'))
    
    def get_ui(self):
        return self.section_container(ft.Column([
            ft.Row([ft.Icon(ft.Icons.CAMERA_ALT), ft.Text("📷 Extraer de Imagen", weight="bold", size=14)]),
            ft.Row([self.btn_pegar, self.btn_seleccionar], spacing=10),
            ft.Container(content=self.image_preview, alignment=ft.alignment.center),
            ft.Container(height=10),
            ft.Text("Ruta manual:", size=12, weight="bold"),
            ft.Row([self.path_input, self.btn_path_load], spacing=10),
            ft.Container(height=10),
            ft.Container(content=self.result_text, padding=ft.padding.only(top=5)),
            ft.Container(content=self.status_text, padding=ft.padding.only(top=5)),
        ], spacing=10))
    
    def _on_paste_click(self, e):
        self.status_text.value = "⏳ Leyendo portapapeles..."
        self.status_text.color = self.theme_colors.get('text_secondary')
        self.page.update()
        
        try:
            clipboard_data = self.page.get_clipboard()
            print(f"[OCR] Clipboard data type: {type(clipboard_data)}, length: {len(str(clipboard_data)) if clipboard_data else 0}")
            
            if not clipboard_data:
                self.status_text.value = "❌ Portapapeles vacío"
                self.status_text.color = self.theme_colors.get('error')
                self.page.update()
                return
            
            image_path = None
            
            # If it's a string (might be a file path)
            if isinstance(clipboard_data, str):
                if os.path.exists(clipboard_data):
                    image_path = clipboard_data
                    print(f"[OCR] Using clipboard path: {image_path}")
                else:
                    # Try to decode as base64 image
                    try:
                        import base64
                        img_bytes = base64.b64decode(clipboard_data)
                        import tempfile
                        temp_dir = tempfile.gettempdir()
                        image_path = os.path.join(temp_dir, "ocr_clipboard.png")
                        with open(image_path, 'wb') as f:
                            f.write(img_bytes)
                        print(f"[OCR] Saved base64 image to: {image_path}")
                    except Exception as decode_err:
                        print(f"[OCR] Not base64: {decode_err}")
            
            # If it's bytes, save as temp file
            elif isinstance(clipboard_data, bytes):
                import tempfile
                temp_dir = tempfile.gettempdir()
                image_path = os.path.join(temp_dir, "ocr_clipboard.png")
                with open(image_path, 'wb') as f:
                    f.write(clipboard_data)
                print(f"[OCR] Saved clipboard bytes to: {image_path}")
            
            if not image_path or not os.path.exists(image_path):
                self.status_text.value = "❌ No hay imagen en portapapeles"
                self.status_text.color = self.theme_colors.get('error')
                print(f"[OCR] Invalid clipboard data")
                self.page.update()
                return
            
            self._process_image(image_path)
            
        except Exception as ex:
            import traceback
            print(f"[OCR] Paste error: {ex}\n{traceback.format_exc()}")
            self.status_text.value = f"Error: {str(ex)}"
            self.status_text.color = self.theme_colors.get('error')
            self.page.update()
    
    def _on_select_click(self, e):
        self.file_picker.pick_files(allowed_extensions=["png", "jpg", "jpeg", "bmp", "webp"])
    
    def _on_file_select(self, e):
        print(f"[OCR] File selected: {e.files}")
        if not e.files:
            self.status_text.value = "❌ Sin archivos"
            self.status_text.color = self.theme_colors.get('error')
            self.page.update()
            return
        
        f = e.files[0]
        print(f"[OCR] File: name={f.name}, path={getattr(f, 'path', None)}, size={getattr(f, 'size', 0)}")
        
        image_path = None
        
        # Try path attribute (desktop)
        if hasattr(f, 'path') and f.path:
            image_path = f.path
            print(f"[OCR] Using path: {image_path}")
        
        # Try data attribute (web mode)
        if not image_path and hasattr(f, 'data') and f.data:
            import tempfile
            temp_dir = tempfile.gettempdir()
            ext = f.name.split('.')[-1] if f.name else 'jpg'
            image_path = os.path.join(temp_dir, f"ocr_{f.id if hasattr(f, 'id') else 'upload'}.{ext}")
            try:
                with open(image_path, 'wb') as fp:
                    fp.write(f.data)
                print(f"[OCR] Saved data to: {image_path}")
            except Exception as save_err:
                print(f"[OCR] Error saving data: {save_err}")
                image_path = None
        
        # Try using name as path (fallback)
        if not image_path and f.name:
            import tempfile
            temp_dir = tempfile.gettempdir()
            image_path = os.path.join(temp_dir, f.name)
            print(f"[OCR] Trying name-based path: {image_path}")
            if not os.path.exists(image_path):
                image_path = None
        
        if not image_path or not os.path.exists(image_path):
            self.status_text.value = "❌ No se pudo acceder al archivo"
            self.status_text.color = self.theme_colors.get('error')
            print(f"[OCR] Could not access file. name={f.name}, path={getattr(f, 'path', None)}")
            self.page.update()
            return
        
        self._process_image(image_path)
    
    def _on_path_submit(self, e):
        image_path = self.path_input.value.strip() if self.path_input.value else ""
        print(f"[OCR] Manual path submitted: {image_path}")
        if not image_path:
            self.status_text.value = "❌ Ingrese una ruta"
            self.status_text.color = self.theme_colors.get('error')
            self.page.update()
            return
        self._process_image(image_path)
    
    def _on_path_load_click(self, e):
        image_path = self.path_input.value.strip() if self.path_input.value else ""
        print(f"[OCR] Manual path load clicked: {image_path}")
        if not image_path:
            self.status_text.value = "❌ Ingrese la ruta del archivo"
            self.status_text.color = self.theme_colors.get('error')
            self.page.update()
            return
        self._process_image(image_path)
    
    def _process_image(self, image_path):
        print(f"[OCR] Processing image: {image_path}")
        
        if not image_path or not os.path.exists(image_path):
            self.status_text.value = "❌ Ruta inválida"
            self.status_text.color = self.theme_colors.get('error')
            print(f"[OCR] Invalid path: {image_path}")
            self.page.update()
            return
        
        try:
            self.image_preview.visible = True
            self.image_preview.content = ft.Image(src=image_path, width=200, height=100, fit="contain")
            self.page.update()
            print(f"[OCR] Image preview updated")
        except Exception as preview_err:
            print(f"[OCR] Preview error: {preview_err}")
        
        try:
            from usr.ocr_extractor import extract_from_image, check_proveedor_exists
            print(f"[OCR] Starting OCR extraction")
            datos = extract_from_image(image_path)
            print(f"[OCR] Extracted data: {datos}")
            
            resultado = f"Proveedor: {datos.get('proveedor', 'N/A')}\n"
            resultado += f"RIF: {datos.get('rif', 'N/A')}\n"
            resultado += f"Factura: {datos.get('nro_factura', 'N/A')}\n"
            resultado += f"Fecha: {datos.get('fecha', 'N/A')}"
            self.result_text.value = resultado
            self.result_text.update()
            
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
            print(f"[OCR] Success")
        except Exception as ex:
            import traceback
            error_details = traceback.format_exc()
            print(f"[OCR ERROR] {str(ex)}\n{error_details}")
            self.status_text.value = f"Error: {str(ex)}"
            self.status_text.color = self.theme_colors.get('error')
        finally:
            self.page.update()