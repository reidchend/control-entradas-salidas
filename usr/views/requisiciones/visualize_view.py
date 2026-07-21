import flet as ft
from datetime import datetime
from usr.theme import get_colors
from usr.views.requisiciones.helpers import _colors, _c
from usr.views.requisiciones.data import get_detalles
from usr.notifications import show_success, show_info, show_warning


class VisualizeView(ft.Container):
    def __init__(self, req, on_back):
        super().__init__()
        self.req = req
        self.on_back = on_back
        self.expand = True
        self.padding = 20
        self._file_picker = None
        self._build_ui()

    def _build_ui(self):
        colors = _colors(self.page)
        detalles = get_detalles(self.req.id)

        header = ft.Row([
            ft.IconButton(
                ft.Icons.ARROW_BACK_IOS_NEW_ROUNDED, 
                on_click=lambda _: self.on_back(), 
                icon_color=colors['text_primary'],
                tooltip="Volver"
            ),
            ft.Column([
                ft.Text(f"Requisición #{self.req.numero}", size=22, weight="bold", color=colors['text_primary']),
                ft.Text(f"Estado: {self.req.estado.upper()}", size=14, color=colors['text_secondary']),
            ], spacing=0, expand=True),
            ft.PopupMenuButton(
                items=[
                    ft.PopupMenuItem(
                        icon=ft.Icons.CONTENT_COPY,
                        text="Copiar al portapapeles",
                        on_click=lambda _: self._copy_to_clipboard(),
                    ),
                    ft.PopupMenuItem(
                        icon=ft.Icons.SAVE_ALT,
                        text="Guardar como .txt",
                        on_click=lambda _: self._save_as_txt(),
                    ),
                ],
                icon=ft.Icons.SHARE,
                tooltip="Compartir requisición",
                icon_color=colors['text_primary'],
            ),
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN)

        info_card = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Text("Origen:", weight="bold", color=colors['text_secondary'], width=100),
                    ft.Text(self.req.origen, color=colors['text_primary'], expand=True, overflow=ft.TextOverflow.ELLIPSIS),
                ]),
                ft.Row([
                    ft.Text("Destino:", weight="bold", color=colors['text_secondary'], width=100),
                    ft.Text(self.req.destino, color=colors['text_primary'], expand=True, overflow=ft.TextOverflow.ELLIPSIS),
                ]),
                ft.Row([
                    ft.Text("Observaciones:", weight="bold", color=colors['text_secondary'], width=100),
                    ft.Text(self.req.observaciones or "Sin observaciones", color=colors['text_primary'], expand=True),
                ]),
            ], spacing=10),
            padding=20,
            bgcolor=colors['card'],
            border_radius=12,
            border=ft.border.all(1, colors['border']),
        )

        detalles_list = ft.Column([
            ft.Text("Detalles de Productos", size=18, weight="bold", color=colors['text_primary']),
            ft.Divider(height=1, color=colors['border']),
        ], spacing=10)

        for d in detalles:
            detalles_list.controls.append(
                ft.Container(
                    content=ft.Row([
                        ft.Text(d.ingrediente, expand=True, color=colors['text_primary']),
                        ft.Text(f"{d.cantidad:.2f} {d.unidad}", weight="bold", color=colors['accent']),
                    ]),
                    padding=10,
                    bgcolor=colors['bg'],
                    border_radius=8,
                    border=ft.border.all(1, colors['border']),
                )
            )

        self.content = ft.Column([
            header,
            ft.Container(height=10),
            info_card,
            ft.Container(height=20),
            detalles_list,
        ], scroll=ft.ScrollMode.AUTO, spacing=20)
        self.bgcolor = colors['bg']

    def _get_file_picker(self):
        """Crea el FilePicker bajo demanda (lazy) cuando self.page ya existe."""
        if self._file_picker is None:
            self._file_picker = ft.FilePicker(on_result=self._on_file_save_result)
            self.page.overlay.append(self._file_picker)
        return self._file_picker

    def _copy_to_clipboard(self):
        """Genera el texto de la requisición y lo copia al portapapeles."""
        try:
            import pyperclip
            texto = self._generar_texto_requisicion()
            pyperclip.copy(texto)
            show_success("Requisición copiada al portapapeles")
        except ImportError:
            # Fallback si no está pyperclip
            self.page.set_clipboard(self._generar_texto_requisicion())
            show_success("Requisición copiada al portapapeles")
        except Exception as e:
            show_warning(f"No se pudo copiar: {e}")

    def _save_as_txt(self):
        """Abre el diálogo para guardar como archivo .txt."""
        picker = self._get_file_picker()
        picker.save_file(
            dialog_title="Guardar requisición como .txt",
            file_name=f"REQ-{self.req.numero}.txt",
            allowed_extensions=["txt"],
        )

    def _on_file_save_result(self, e: ft.FilePickerResultEvent):
        """Callback cuando el usuario selecciona dónde guardar el archivo."""
        if e.path:
            try:
                with open(e.path, "w", encoding="utf-8") as f:
                    f.write(self._generar_texto_requisicion())
                show_success(f"Requisición guardada en:\n{e.path}")
            except Exception as ex:
                show_warning(f"Error al guardar archivo: {ex}")

    def _generar_texto_requisicion(self) -> str:
        """Genera el texto limpio de la requisición para compartir (WhatsApp-friendly)."""
        from datetime import datetime
        lines = []
        lines.append(f"📋 *REQUISICIÓN #{self.req.numero}*")
        lines.append(f"Estado: *{self.req.estado.upper()}*")
        lines.append(f"📦 {self.req.origen} → {self.req.destino}")
        if getattr(self.req, 'fecha_creacion', None):
            if isinstance(self.req.fecha_creacion, str):
                lines.append(f"📅 {self.req.fecha_creacion}")
            else:
                lines.append(f"📅 {self.req.fecha_creacion.strftime('%d/%m/%Y %H:%M')}")
        if self.req.observaciones:
            lines.append(f"📝 {self.req.observaciones}")
        lines.append("")
        lines.append("*Productos:*")
        
        detalles = get_detalles(self.req.id)
        for d in detalles:
            cant_str = f"{d.cantidad:.2f} {d.unidad}".rstrip('0').rstrip('.')
            lines.append(f"• {d.ingrediente} — {cant_str}")
        
        lines.append("")
        lines.append(f"_Generado: {datetime.now().strftime('%d/%m/%Y %H:%M')}_")
        return "\n".join(lines)
