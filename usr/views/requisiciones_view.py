import warnings
warnings.filterwarnings("ignore", category=PendingDeprecationWarning)

import asyncio
import flet as ft
from usr.database.base import get_db_adaptive
from usr.database.sync_callbacks import register_sync_callback, unregister_sync_callback
from usr.models import Requisicion
import logging
from usr.theme import get_theme, get_colors
from usr.notifications import show_error, show_warning
from usr.views.requisiciones.cards import build_requisicion_card
from usr.views.requisiciones.dialogs import RequisicionDetailDialog
from usr.views.requisiciones.form import RequisicionForm
from usr.views.requisiciones.service import RequisicionService

logger = logging.getLogger(__name__)


def _colors(page):
    return get_colors(page)


def _get_color(page, color_name):
    colors = _colors(page)
    color_map = {
        'GREY_300': colors['text_hint'],
        'GREY_400': colors['text_secondary'],
        'GREY_500': colors['text_secondary'],
        'GREY_200': colors['border'],
        'GREY_50': colors['bg'],
        'BLUE_GREY_900': colors['text_primary'],
        'BLUE_GREY_800': colors['text_primary'],
        'BLUE_GREY_500': colors['text_secondary'],
        'BLUE_GREY_400': colors['text_secondary'],
        'WHITE': colors['white'],
        'BLUE_600': colors['accent'],
        'BLUE_700': colors['accent'],
        'GREEN_600': colors['success'],
        'GREEN_700': colors['success'],
        'RED_400': colors['error'],
        'RED_700': colors['error'],
        'ORANGE_600': colors['warning'],
        'ORANGE_700': colors['warning'],
    }
    return color_map.get(color_name, colors['text_primary'])


def _c(page, color_name):
    return _get_color(page, color_name)


class RequisicionesView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.bgcolor = '#1A1A1A'
        self.padding = 0

        self.requisiciones_list = ft.ListView(expand=True, spacing=10, padding=20)
        self.active_dialog = None
        self.inventario_view = None
        self.app_controller: any = None

        self._vista_actual = "lista"
        self._current_form = None

    def on_theme_change(self):
        if not self.page:
            return
        colors = _colors(self.page)
        self.bgcolor = colors['bg']
        try:
            self._build_ui()
            self._load_requisiciones()
        except:
            pass

    def _build_ui(self):
        colors = _colors(self.page)
        header = ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Text("Requisiciones", size=26, weight="bold", color=colors['text_primary']),
                    ft.Text("Gestión de traslados", size=13, color=colors['text_secondary']),
                ], expand=True, spacing=0),
                ft.IconButton(
                    ft.Icons.ADD_ROUNDED,
                    icon_color=colors['white'],
                    bgcolor=colors['accent'],
                    on_click=lambda _: self._show_crear_vista(),
                    tooltip="Nueva requisición",
                ),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            padding=ft.padding.only(left=20, right=20, top=20, bottom=10),
            bgcolor=colors['surface'],
        )

        self.list_container = ft.Container(
            content=self.requisiciones_list,
            expand=True,
            bgcolor=colors['bg'],
        )

        self.content = ft.Column([
            header,
            self.list_container,
        ], expand=True, spacing=0)
        self.content.bgcolor = colors['bg']

        self.update()
        self._load_requisiciones()

    def did_mount(self):
        try:
            self._build_ui()
            register_sync_callback(self._on_sync_complete)
        except Exception as e:
            from usr.error_handler import show_error
            show_error("Error al montar vista de requisiciones", e, "requisiciones_view.did_mount")

    def will_unmount(self):
        unregister_sync_callback(self._on_sync_complete)

    def _on_sync_complete(self):
        if hasattr(self, 'page') and self.page and self.visible:
            if self._vista_actual == "lista":
                async def _reload():
                    await asyncio.to_thread(self._load_requisiciones)
                self.page.run_task(_reload)

    def on_sync_complete(self):
        self._on_sync_complete()

    def _load_requisiciones(self):
        db = next(get_db_adaptive())
        try:
            reqs = RequisicionService.get_all_requisiciones(db)

            self.requisiciones_list.controls.clear()

            if not reqs:
                colors = _colors(self.page)
                self.requisiciones_list.controls.append(
                    ft.Container(
                        content=ft.Column([
                            ft.Icon(ft.Icons.INVENTORY_2_OUTLINED, size=50, color=colors['text_hint']),
                            ft.Text("No hay requisiciones", color=colors['text_secondary']),
                        ], horizontal_alignment="center"),
                        padding=ft.padding.only(top=80),
                        alignment=ft.alignment.top_center,
                    )
                )
            else:
                for req in reqs:
                    card = build_requisicion_card(
                        req, self.page,
                        on_ver=self._show_detalles,
                        on_editar=self._editar_requisicion,
                        on_click=self._show_detalles,
                    )
                    self.requisiciones_list.controls.append(card)

            self.requisiciones_list.update()
            self.list_container.update()
            if self.page:
                self.page.update()
        except Exception as e:
            show_error("Error cargando requisiciones", e, "requisiciones_view._load_requisiciones")
        finally:
            db.close()

    def _show_crear_vista(self, requisicion=None):
        self._vista_actual = "crear"

        form = RequisicionForm(
            page=self.page,
            on_back=self._volver_lista,
            on_saved=self._on_form_saved,
            requisicion=requisicion,
        )
        self._current_form = form
        self.content = form.build()
        self.update()

    def _editar_requisicion(self, req):
        if not self.page:
            return
        if req.estado == "completada":
            show_warning("No se puede editar una requisición completada")
            self.page.update()
            return
        self._show_crear_vista(requisicion=req)

    def _show_detalles(self, req):
        if not self.page:
            return
        dialog = RequisicionDetailDialog(self.page, req)
        dialog.show()

    def _on_form_saved(self):
        self._volver_lista()

    def _volver_lista(self):
        self._vista_actual = "lista"
        self._current_form = None
        self._build_ui()
        self.update()
