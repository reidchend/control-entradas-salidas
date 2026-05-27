import flet as ft
import os
import io
import base64
import tempfile
from PIL import ImageGrab, Image


def _notify_error(msg, ex=None, page=None):
    try:
        from usr.notifications import show_error_with_copy
        from usr.ocr_extractor import _gemini_error
        final_msg = msg
        if _gemini_error:
            final_msg = "OCR.SPACE agotado + Gemini sin clave. Agrega GEMINI_API_KEY en tu archivo .env"
        show_error_with_copy(final_msg, ex)
    except Exception:
        print(f"[ERROR] {msg}: {ex}")


def _get_long_path(path):
    try:
        import ctypes
        GetLongPathName = ctypes.windll.kernel32.GetLongPathNameW
        buf = ctypes.create_unicode_buffer(512)
        result = GetLongPathName(path, buf, 512)
        return buf.value if result else path
    except Exception:
        return path


class OCRHandler:
    def __init__(self, page, theme_colors, fields=None):
        self.page = page
        self.theme_colors = theme_colors
        self.fields = fields
        self.my_company_name = "LA POSADA DE DANIEL"
        self.my_company_rif = "J316636151"
        try:
            self._build_ui()
        except Exception as ex:
            print(f"[ERROR] OCRHandler.__init__: {ex}")
            import traceback; traceback.print_exc()
            _notify_error("Error inicializando OCR", ex)

    def _build_ui(self):
        self.image_preview = ft.Container(
            content=ft.Column([
                ft.Icon(ft.Icons.IMAGE_OUTLINED, size=40, color=self.theme_colors.get('text_hint')),
                ft.Text("Vista previa de factura", size=12, color=self.theme_colors.get('text_hint'))
            ], alignment=ft.MainAxisAlignment.CENTER, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
            width=350,
            height=180,
            bgcolor=self.theme_colors.get('surface_variant', '#1e1e1e'),
            border=ft.border.all(1, self.theme_colors.get('border')),
            border_radius=12,
            margin=ft.margin.only(bottom=10)
        )

        self.loading_bar = ft.ProgressBar(
            width=350,
            color=self.theme_colors.get('primary', ft.Colors.PURPLE),
            bgcolor=ft.Colors.TRANSPARENT,
            visible=False
        )

        self.result_display = ft.Text(
            "Esperando documento...",
            size=12,
            color=self.theme_colors.get('text_secondary'),
            italic=True
        )

        self.status_text = ft.Text(
            "",
            size=11,
            weight="w500"
        )

        self.btn_pegar = ft.ElevatedButton(
            "Pegar Imagen",
            icon=ft.Icons.CONTENT_PASTE,
            style=ft.ButtonStyle(shape=ft.RoundedRectangleBorder(radius=8)),
            on_click=self._on_paste_click
        )

        self.btn_seleccionar = ft.TextButton(
            "Subir archivo",
            icon=ft.Icons.UPLOAD_FILE,
            on_click=self._on_select_click
        )

        self.btn_limpiar = ft.IconButton(
            icon=ft.Icons.DELETE_SWEEP_OUTLINED,
            icon_color=ft.Colors.RED_400,
            tooltip="Limpiar OCR",
            on_click=self._on_clear_click
        )

        self.file_picker = ft.FilePicker(on_result=self._on_file_select)
        self.page.overlay.append(self.file_picker)
        self.current_image_path = None

    def section_container(self, content):
        return ft.Container(
            content=content,
            padding=15,
            border_radius=15,
            border=ft.border.all(1, self.theme_colors.get('border', '#333333')),
            bgcolor=self.theme_colors.get('surface', '#252525')
        )

    def get_ui(self):
        return self.section_container(
            ft.Column([
                ft.Row([
                    ft.Icon(ft.Icons.SCANNER, size=20, color=self.theme_colors.get('primary')),
                    ft.Text("Asistente de Lectura (AI)", weight="bold", size=15),
                    ft.VerticalDivider(),
                    self.btn_limpiar
                ], alignment=ft.MainAxisAlignment.START),

                ft.Divider(height=1, color=self.theme_colors.get('border')),

                ft.Container(height=10),

                ft.Column([
                    self.image_preview,
                    self.loading_bar,
                    self.status_text,
                ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),

                ft.Container(height=5),

                ft.Row([
                    self.btn_pegar,
                    self.btn_seleccionar,
                ], alignment=ft.MainAxisAlignment.CENTER, spacing=10),

                ft.Container(
                    content=self.result_display,
                    padding=10,
                    bgcolor=ft.Colors.with_opacity(0.1, ft.Colors.BLACK),
                    border_radius=8,
                    width=350
                )
            ], spacing=5, horizontal_alignment=ft.CrossAxisAlignment.CENTER)
        )

    def _set_loading(self, loading: bool, message: str = ""):
        try:
            self.loading_bar.visible = loading
            self.btn_pegar.disabled = loading
            self.btn_seleccionar.disabled = loading
            if message:
                self.status_text.value = message
                self.status_text.color = self.theme_colors.get('text_secondary')
            self.page.update()
        except Exception as ex:
            print(f"[ERROR] OCRHandler._set_loading: {ex}")

    def _on_paste_click(self, e):
        try:
            self._set_loading(True, "Accediendo al portapapeles...")
            img = ImageGrab.grabclipboard()
            if img is None:
                self._set_loading(False, "Error: No hay imagen en el portapapeles")
                self.status_text.color = ft.Colors.RED_400
                return

            buffered = io.BytesIO()
            img.save(buffered, format="PNG")
            img_base64 = base64.b64encode(buffered.getvalue()).decode("utf-8")

            temp_dir = _get_long_path(tempfile.gettempdir())
            temp_path = os.path.join(temp_dir, "ocr_temp.png")
            img.save(temp_path, 'PNG')
            self.current_image_path = temp_path
            print(f"[OCR] Imagen guardada: {temp_path} ({os.path.getsize(temp_path) // 1024}KB)")

            self.image_preview.content = ft.Image(
                src_base64=img_base64,
                fit=ft.ImageFit.CONTAIN,
                border_radius=8
            )
            self._process_image(temp_path)

        except Exception as ex:
            print(f"[ERROR] OCRHandler._on_paste_click: {ex}")
            import traceback; traceback.print_exc()
            self._set_loading(False, f"Error de pegado: {str(ex)[:50]}")
            self.status_text.color = ft.Colors.RED_400
            _notify_error("Error al pegar imagen del portapapeles", ex)

    def _on_select_click(self, e):
        try:
            self.file_picker.pick_files(allowed_extensions=["png", "jpg", "jpeg"])
        except Exception as ex:
            print(f"[ERROR] OCRHandler._on_select_click: {ex}")
            _notify_error("Error al abrir selector de archivo", ex)

    def _on_file_select(self, e):
        try:
            if e.files:
                self._set_loading(True, "Cargando archivo...")
                path = _get_long_path(e.files[0].path)
                self.image_preview.content = ft.Image(src=path, fit=ft.ImageFit.CONTAIN, border_radius=8)
                self.current_image_path = path
                print(f"[OCR] Imagen seleccionada: {path}")
                self._process_image(path)
        except Exception as ex:
            print(f"[ERROR] OCRHandler._on_file_select: {ex}")
            import traceback; traceback.print_exc()
            self._set_loading(False, "Error al cargar archivo")
            self.status_text.color = ft.Colors.RED_400
            _notify_error("Error al procesar archivo seleccionado", ex)

    def _process_image(self, path):
        try:
            self._set_loading(True, "AI analizando documento...")

            from usr.ocr_extractor import extract_from_image, check_proveedor_exists

            datos = extract_from_image(path)

            has_data = any(datos.values())
            self.result_display.value = (
                f"🏷️ {datos.get('proveedor', 'No hallado')}\n"
                f"🆔 RIF: {datos.get('rif', 'No hallado')}\n"
                f"📄 Doc: {datos.get('nro_factura', '---')}\n"
                f"📅 Fecha: {datos.get('fecha', '---')}"
            )
            self.result_display.italic = False

            if not has_data:
                self._set_loading(False, "⚠️ OCR no detectó datos")
                self.status_text.value = "⚠️ No se extrajeron datos de la imagen. Puedes ingresar los datos manualmente."
                self.status_text.color = ft.Colors.ORANGE_400
                if hasattr(self.fields, 'check_validar_button'):
                    self.fields.check_validar_button()
                return

            if self.fields:
                try:
                    if datos.get('nro_factura'):
                        self.fields.factura_input.value = datos['nro_factura']
                        if hasattr(self.fields, 'check_validar_button'):
                            self.fields.check_validar_button()
                except Exception as ex:
                    print(f"[WARN] Error llenando factura_input: {ex}")

                try:
                    if datos.get('proveedor'):
                        prov_check = check_proveedor_exists(datos['proveedor'], datos.get('rif', ''))
                        if prov_check['existe']:
                            self.fields.proveedor_dd.value = prov_check['nombre']
                            self.status_text.value = f"✅ Proveedor reconocido: {prov_check['nombre']}"
                        else:
                            self.fields.proveedor_dd.value = "__nuevo__"
                            if hasattr(self.fields, 'nuevo_proveedor_input'):
                                self.fields.nuevo_proveedor_input.visible = True
                                self.fields.nuevo_proveedor_input.value = datos['proveedor']
                            if hasattr(self.fields, 'nuevo_proveedor_rif'):
                                self.fields.nuevo_proveedor_rif.visible = True
                                self.fields.nuevo_proveedor_rif.value = datos.get('rif', '')
                            self.status_text.value = "✨ Nuevo proveedor detectado"
                except Exception as ex:
                    print(f"[WARN] Error llenando proveedor: {ex}")

                try:
                    if hasattr(self.fields, 'check_validar_button'):
                        self.fields.check_validar_button()
                except Exception as ex:
                    print(f"[WARN] Error en check_validar_button post-OCR: {ex}")

            self._set_loading(False, "Procesamiento completado")
            self.status_text.color = self.theme_colors.get('success')

        except Exception as ex:
            print(f"[ERROR] OCRHandler._process_image: {ex}")
            import traceback; traceback.print_exc()
            self._set_loading(False, "Error al procesar con AI")
            self.status_text.color = ft.Colors.RED_400
            _notify_error("Error al procesar imagen con IA", ex)

    def _on_clear_click(self, e):
        try:
            self.image_preview.content = ft.Column([
                ft.Icon(ft.Icons.IMAGE_OUTLINED, size=40, color=self.theme_colors.get('text_hint')),
                ft.Text("Vista previa de factura", size=12, color=self.theme_colors.get('text_hint'))
            ], alignment=ft.MainAxisAlignment.CENTER, horizontal_alignment=ft.CrossAxisAlignment.CENTER)
            self.result_display.value = "Esperando documento..."
            self.result_display.italic = True
            self.status_text.value = ""
            self.current_image_path = None
            self._on_clear_fields()
            self.page.update()
        except Exception as ex:
            print(f"[ERROR] OCRHandler._on_clear_click: {ex}")
            _notify_error("Error al limpiar datos OCR", ex)

    def _on_clear_fields(self):
        try:
            if self.fields:
                self.fields.factura_input.value = ""
                if hasattr(self.fields, 'proveedor_dd'):
                    self.fields.proveedor_dd.value = ""
                if hasattr(self.fields, 'nuevo_proveedor_input'):
                    self.fields.nuevo_proveedor_input.value = ""
                    self.fields.nuevo_proveedor_input.visible = False
                if hasattr(self.fields, 'nuevo_proveedor_rif'):
                    self.fields.nuevo_proveedor_rif.value = ""
                    self.fields.nuevo_proveedor_rif.visible = False
                if hasattr(self.fields, 'check_validar_button'):
                    self.fields.check_validar_button()
            if self.page:
                self.page.update()
        except Exception as ex:
            print(f"[ERROR] OCRHandler._on_clear_fields: {ex}")
            _notify_error("Error al limpiar campos", ex)