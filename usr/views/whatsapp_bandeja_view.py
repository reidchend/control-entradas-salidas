import flet as ft
from usr.theme import get_colors
from usr.whatsapp_notifier import (
    get_queued_messages, count_pending, retry_queued_messages,
    delete_from_queue, update_queue_estado, _send_text_direct, _send_image_direct,
    send_whatsapp_message
)
import datetime


class BandejaWhatsAppView(ft.Container):
    def __init__(self):
        super().__init__()
        self.expand = True
        self.padding = 20
        self._mensajes = []
        self._list_view = ft.ListView(expand=True, spacing=10, padding=10)
        self._pending_badge = ft.Container(
            content=ft.Text("0", size=10, color="white", weight="bold"),
            bgcolor="red", border_radius=10, padding=ft.padding.all(4),
            visible=False
        )
        self.stats_text = ft.Text("Cargando...", size=12)

    def did_mount(self):
        self._load_messages()

    def build(self):
        colors = get_colors(self.page) if self.page else {}
        header = ft.Row([
            ft.Icon(ft.Icons.MAIL_OUTLINED, size=28, color=colors.get('primary', '#BB86FC')),
            ft.Text("📨 Bandeja WhatsApp", size=22, weight="bold"),
            self._pending_badge,
            ft.Container(expand=True),
            ft.ElevatedButton("📤 Probar Bot", icon=ft.Icons.SEND, on_click=self._on_test_bot),
            ft.ElevatedButton("🔄 Reintentar todos", on_click=self._on_retry_all),
        ])
        self.content = ft.Column([
            header,
            self.stats_text,
            ft.Divider(height=1),
            self._list_view,
        ], expand=True, spacing=10)

    def _load_messages(self):
        try:
            self._mensajes = get_queued_messages(limit=100)
            pendientes = count_pending()
            self._pending_badge.visible = pendientes > 0
            self._pending_badge.content = ft.Text(str(pendientes), size=10, color="white", weight="bold")
            total = len(self._mensajes)
            enviados = sum(1 for m in self._mensajes if m['estado'] == 'sent')
            fallidos = sum(1 for m in self._mensajes if m['estado'] == 'failed')
            pend = sum(1 for m in self._mensajes if m['estado'] == 'pending')
            self.stats_text.value = f"Total: {total} | ⏳ Pendientes: {pend} | ✅ Enviados: {enviados} | ❌ Fallidos: {fallidos}"
            self._render_list()
            if self.page:
                self.update()
        except Exception as ex:
            print(f"[BANDEJA] Error cargando mensajes: {ex}")

    def _render_list(self):
        self._list_view.controls.clear()
        colors = get_colors(self.page) if self.page else {}

        if not self._mensajes:
            self._list_view.controls.append(
                ft.Container(
                    content=ft.Column([
                        ft.Icon(ft.Icons.INBOX_OUTLINED, size=60, color=colors.get('text_hint', '#666')),
                        ft.Text("No hay mensajes en la bandeja", size=16, color=colors.get('text_secondary', '#999'))
                    ], alignment=ft.MainAxisAlignment.CENTER, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
                    expand=True, alignment=ft.alignment.center, padding=50
                )
            )
            return

        for msg in self._mensajes:
            card = self._build_card(msg, colors)
            self._list_view.controls.append(card)

    def _build_card(self, msg: dict, colors: dict) -> ft.Container:
        icono = ft.Icon(ft.Icons.IMAGE_OUTLINED, size=24, color=colors.get('primary', '#BB86FC')) if msg['tipo'] == 'image' else \
                ft.Icon(ft.Icons.TEXT_FIELDS, size=24, color=colors.get('accent', '#03DAC6'))

        estado_icono = self._estado_icon(msg['estado'])
        estado_text = self._estado_text(msg)

        preview = msg.get('mensaje', '') or ''
        if len(preview) > 80:
            preview = preview[:80] + '...'

        created = msg.get('created_at', '') or ''
        try:
            dt = datetime.datetime.strptime(created, '%Y-%m-%d %H:%M:%S')
            created = dt.strftime('%d/%m %H:%M')
        except:
            pass

        return ft.Container(
            content=ft.Row([
                icono,
                ft.Column([
                    ft.Row([
                        ft.Container(
                            content=estado_icono,
                            padding=5, border_radius=5,
                            bgcolor=colors.get('surface_variant', '#333')
                        ),
                        ft.Text(estado_text, size=12, weight="bold"),
                        ft.Text(created, size=11, color=colors.get('text_hint', '#777')),
                    ], spacing=8),
                    ft.Text(preview, size=13, color=colors.get('text_primary', '#fff')),
                ], expand=True, spacing=2),
                ft.Column([
                    ft.IconButton(ft.Icons.REPLAY, icon_size=18, on_click=lambda _, mid=msg['id']: self._on_retry_one(mid)),
                    ft.IconButton(ft.Icons.DELETE_OUTLINE, icon_size=18, icon_color=ft.Colors.RED_400,
                                  on_click=lambda _, mid=msg['id']: self._on_delete_one(mid)),
                ], spacing=0),
            ], spacing=10),
            padding=12, border_radius=10,
            bgcolor=colors.get('surface', '#252525'),
            border=ft.border.all(1, colors.get('border', '#333'))
        )

    def _estado_icon(self, estado: str) -> ft.Control:
        if estado == 'sent':
            return ft.Icon(ft.Icons.CHECK_CIRCLE, size=16, color=ft.Colors.GREEN_400)
        elif estado == 'failed':
            return ft.Icon(ft.Icons.ERROR, size=16, color=ft.Colors.RED_400)
        elif estado == 'sending':
            return ft.ProgressRing(width=16, height=16, stroke_width=2)
        else:
            return ft.Icon(ft.Icons.HOURGLASS_EMPTY, size=16, color=ft.Colors.ORANGE_400)

    def _estado_text(self, msg: dict) -> str:
        estado = msg.get('estado', '')
        intentos = msg.get('intentos', 0)
        max_int = msg.get('max_intentos', 10)
        if estado == 'sent':
            return "✅ Enviado"
        elif estado == 'failed':
            return f"❌ Fallido ({intentos}/{max_int})"
        elif estado == 'sending':
            return "⏳ Enviando..."
        else:
            return f"⏳ Pendiente ({intentos}/{max_int})"

    def _on_retry_one(self, msg_id: int):
        msg = next((m for m in self._mensajes if m['id'] == msg_id), None)
        if not msg:
            return
        try:
            update_queue_estado(msg_id, 'sending')
            self._load_messages()
            success = False
            if msg['tipo'] == 'text':
                success = _send_text_direct(msg['mensaje'])
            elif msg['tipo'] == 'image':
                success = _send_image_direct(msg.get('imagen_base64'), msg.get('mensaje', ''), msg.get('imagen_path'))

            if success:
                update_queue_estado(msg_id, 'sent')
                print(f"[BANDEJA] Mensaje {msg_id} reenviado OK")
            else:
                update_queue_estado(msg_id, 'pending', 'Error en reintento manual')
        except Exception as ex:
            print(f"[BANDEJA] Error reintentando {msg_id}: {ex}")
            update_queue_estado(msg_id, 'pending', str(ex))
        self._load_messages()

    def _on_delete_one(self, msg_id: int):
        delete_from_queue(msg_id)
        self._load_messages()

    def _on_retry_all(self, e):
        retry_queued_messages()
        self._load_messages()

    def _on_test_bot(self, e):
        try:
            from usr.database.local_replica import LocalReplica
            usuario = LocalReplica.get_usuario_dispositivo()
            nombre = usuario['nombre'] if usuario else 'Sistema'
            msg = f"🤖 *Bot activo*\n👤 {nombre}\n🕐 {datetime.datetime.now().strftime('%d/%m %H:%M')}"
            ok = send_whatsapp_message(msg)
            if ok:
                from usr.notifications import show_success
                show_success("✅ Mensaje de prueba enviado")
            else:
                from usr.notifications import show_warning
                show_warning("⚠️ No se pudo enviar. Revisa que el bot esté conectado.")
        except Exception as ex:
            print(f"[BANDEJA] Error test bot: {ex}")
            from usr.notifications import show_error
            show_error(f"Error: {str(ex)}")
