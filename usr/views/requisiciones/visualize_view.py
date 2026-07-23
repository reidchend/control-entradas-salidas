import flet as ft
from urllib.parse import quote
from usr.theme import get_colors
from usr.views.requisiciones.helpers import _colors, _c
from usr.views.requisiciones.data import get_detalles
from usr.notifications import show_success, show_error

class VisualizeView(ft.Container):
    def __init__(self, req, on_back):
        super().__init__()
        self.req = req
        self.on_back = on_back
        self.expand = True
        self.padding = 20
        self._build_ui()

    def _build_mensaje(self):
        """Construye el texto de la requisición para compartir por WhatsApp."""
        detalles = get_detalles(self.req.id)
        lines = [
            f"*Requisición #{self.req.numero}*",
            f"Estado: {self.req.estado.upper()}",
            f"Origen: {self.req.origen}",
            f"Destino: {self.req.destino}",
        ]
        if self.req.observaciones:
            lines.append(f"Observaciones: {self.req.observaciones}")
        lines.append("")
        lines.append("*Detalles:*")
        for d in detalles:
            lines.append(f"• {d.ingrediente}: {d.cantidad:.2f} {d.unidad}")
        return "\n".join(lines)

    def _on_compartir(self, _):
        try:
            msg = self._build_mensaje()
            if self.page:
                self.page.launch_url(f"https://wa.me/?text={quote(msg)}")
                show_success("Abriendo WhatsApp...")
        except Exception as e:
            show_error(f"Error al compartir: {e}")

    def _on_copiar(self, _):
        try:
            msg = self._build_mensaje()
            if self.page:
                self.page.set_clipboard(msg)
                show_success("Requisición copiada al portapapeles")
        except Exception as e:
            show_error(f"Error al copiar: {e}")

    def _build_ui(self):
        colors = _colors(self.page)
        detalles = get_detalles(self.req.id)
        
        header = ft.Row([
            ft.IconButton(ft.Icons.ARROW_BACK_IOS_NEW_ROUNDED, on_click=lambda _: self.on_back(), icon_color=colors['text_primary']),
            ft.Column([
                ft.Text(f"Requisición #{self.req.numero}", size=22, weight="bold", color=colors['text_primary']),
                ft.Text(f"Estado: {self.req.estado.upper()}", size=14, color=colors['text_secondary']),
            ], spacing=0, expand=True),
            ft.PopupMenuButton(
                icon=ft.Icons.SHARE_ROUNDED,
                icon_color=colors['accent'],
                tooltip="Compartir",
                items=[
                    ft.PopupMenuItem(
                        text="Compartir por WhatsApp",
                        icon=ft.Icons.CHAT,
                        on_click=self._on_compartir,
                    ),
                    ft.PopupMenuItem(
                        text="Copiar al portapapeles",
                        icon=ft.Icons.CONTENT_COPY,
                        on_click=self._on_copiar,
                    ),
                ],
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
