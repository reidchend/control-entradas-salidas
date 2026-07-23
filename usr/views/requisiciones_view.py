import warnings
warnings.filterwarnings("ignore", category=PendingDeprecationWarning)

import asyncio
import logging
import traceback
import flet as ft
from datetime import datetime

from usr.database.base import get_db_adaptive
from usr.database.sync_callbacks import register_sync_callback, unregister_sync_callback
from usr.models import Requisicion, RequisicionDetalle, Producto, Existencia
from usr.theme import get_colors
from usr.notifications import show_success, show_error, show_warning, show_info

from usr.views.requisiciones.helpers import _colors, _c
from usr.views.requisiciones.data import load_requisiciones, guardar_requisicion, eliminar_requisicion
from usr.views.requisiciones.components import (
    build_requisicion_card, build_empty_state, build_producto_busqueda_item
)
from usr.views.requisiciones.dialogs import (
    build_crear_dialog, build_agregar_producto_dialog, build_detalles_dialog,
    build_crear_vista, build_buscador_productos, build_agregar_producto_req_dialog,
)
from usr.views.requisiciones.visualize_view import VisualizeView
from usr.views.requisiciones.audit_view import AuditView

logger = logging.getLogger(__name__)


class RequisicionesView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.bgcolor = '#1A1A1A'
        self.padding = 0

        self.requisiciones_list = ft.ListView(expand=True, spacing=10, padding=20)
        self.detalles_temp = []
        self.active_dialog = None
        self.inventario_view = None
        self.app_controller = None

        self._vista_actual = "lista"
        self.lista_productos_req = []
        self._requisicion_editando = None
        self._origen_dropdown = None
        self._productos_lista_req = None
        self._bs_buscador = None

    def on_theme_change(self):
        if not self.page:
            return
        colors = _colors(self.page)
        self.bgcolor = colors['bg']
        try:
            self._build_ui()
        except Exception:
            pass

    def _build_ui(self):
        self.colors = _colors(self.page)
        header = ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Text("Requisiciones", size=26, weight="bold", color=self.colors['text_primary']),
                    ft.Text("Gestión de traslados", size=13, color=self.colors['text_secondary']),
                ], expand=True, spacing=0),
                ft.IconButton(
                    ft.Icons.REFRESH_ROUNDED,
                    icon_color=self.colors['white'],
                    bgcolor=self.colors['surface'],
                    on_click=lambda _: self._on_refresh(),
                    tooltip="Actualizar desde Supabase",
                ),
                ft.IconButton(
                    ft.Icons.ADD_ROUNDED,
                    icon_color=self.colors['white'],
                    bgcolor=self.colors['accent'],
                    on_click=lambda _: self._show_crear_vista(),
                    tooltip="Nueva requisición",
                ),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            padding=ft.padding.only(left=20, right=20, top=20, bottom=10),
            bgcolor=self.colors['surface'],
        )

        self.list_container = ft.Container(
            content=self.requisiciones_list,
            expand=True,
            bgcolor=self.colors['bg'],
        )

        self.content = ft.Column([
            header,
            self.list_container,
        ], expand=True, spacing=0)
        self.content.bgcolor = self.colors['bg']
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

    def _on_refresh(self):
        """Fuerza una sincronización con Supabase y recarga la lista."""
        try:
            show_info("Actualizando requisiciones...", duration=1)
            self.page.run_task(self._do_refresh)
        except Exception as e:
            show_error("Error al refrescar", e)

    async def _do_refresh(self):
        try:
            from usr.database.base import is_online as base_is_online
            from usr.database import get_sync_manager

            if base_is_online():
                sync_mgr = get_sync_manager()
                if sync_mgr:
                    await asyncio.to_thread(sync_mgr.force_sync_now)
            else:
                await asyncio.to_thread(self._load_requisiciones)
                show_success("Requisiciones actualizadas")
        except Exception as e:
            logger.error(f"Error en _do_refresh de RequisicionesView: {e}")
            show_error("Error al actualizar requisiciones", e)

    def _load_requisiciones(self):
        try:
            reqs = load_requisiciones()

            self.requisiciones_list.controls.clear()

            if not reqs:
                self.requisiciones_list.controls.append(build_empty_state(_colors(self.page)))
            else:
                for req in reqs:
                    self.requisiciones_list.controls.append(
                        build_requisicion_card(
                            req,
                            {
                                "on_visualizar": lambda _=None, r=req: self._visualizar_requisicion(r),
                                "on_editar": lambda _=None, r=req: self._editar_requisicion(r),
                                "on_auditar": lambda _=None, r=req: self._auditar_requisicion(r),
                                "on_eliminar": lambda _=None, r=req: self._eliminar_requisicion(r),
                            },
                            _colors(self.page),
                        )
                    )

            if self.requisiciones_list.page:
                self.requisiciones_list.update()
            if self.list_container and self.list_container.page:
                self.list_container.update()
            if self.page:
                self.page.update()
        except Exception as e:
            import traceback
            traceback.print_exc()

    def _editar_requisicion(self, req: Requisicion):
        if not self.page:
            return
        if req.estado == "completada":
            show_warning("No se puede editar una requisición completada")
            return
        self._show_crear_vista(requisicion=req)

    def _eliminar_requisicion(self, req: Requisicion):
        if not self.page:
            return
            
        def confirm_delete(_):
            if eliminar_requisicion(req.id):
                show_success(f"Requisición {req.numero} eliminada")
                import threading
                try:
                    from usr.database import get_sync_manager
                    sync_mgr = get_sync_manager()
                    if sync_mgr:
                        threading.Thread(target=sync_mgr.force_sync_now, daemon=True).start()
                except Exception:
                    pass
                self._load_requisiciones()
            else:
                show_error("Error al eliminar la requisición")
            dlg.open = False
            self.page.update()

        dlg = ft.AlertDialog(
            title=ft.Text("Eliminar Requisición"),
            content=ft.Text(f"¿Estás seguro de que deseas eliminar la requisición {req.numero}? Esta acción no se puede deshacer."),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: setattr(dlg, 'open', False)),
                ft.ElevatedButton("Eliminar", on_click=confirm_delete, bgcolor=self.colors['error'], color=self.colors['white']),
            ]
        )
        self.page.overlay.append(dlg)
        dlg.open = True
        self.page.update()

    def _visualizar_requisicion(self, req: Requisicion):
        self._vista_actual = "visualizar"
        self.content = VisualizeView(req, on_back=self._volver_lista)
        self.update()

    def _auditar_requisicion(self, req: Requisicion):
        if req.estado != "pendiente":
            show_warning("Solo se pueden auditar requisiciones pendientes")
            return
        self._vista_actual = "auditar"
        self.content = AuditView(req.id, on_back=self._volver_lista)
        self.update()

    def _show_crear_dialog(self):
        build_crear_dialog(self)

    def _show_agregar_producto_dialog(self, productos_container):
        build_agregar_producto_dialog(self, productos_container)

    def _eliminar_producto_row(self, btn, container):
        for fila in container.controls:
            if btn in fila.controls:
                container.controls.remove(fila)
                container.update()
                break

    def _filtrar_productos_busqueda(self, texto, productos, container, on_agregar=None):
        colors = _colors(self.page)
        on_agregar = on_agregar or (lambda p: None)
        container.controls.clear()

        if not texto or len(texto) < 1:
            for p in productos[:20]:
                container.controls.append(build_producto_busqueda_item(p, on_agregar, colors))
        else:
            texto_lower = texto.lower()
            filtrados = [p for p in productos if texto_lower in p.nombre.lower()]
            for p in filtrados[:20]:
                container.controls.append(build_producto_busqueda_item(p, on_agregar, colors))

        container.update()

    def _cerrar_dialog(self, dialog):
        dialog.open = False
        self.page.update()

    def _close_dialog(self):
        if self.active_dialog:
            self.active_dialog.open = False
            self.page.update()

    def _show_detalles(self, req: Requisicion):
        build_detalles_dialog(self, req)

    def _show_crear_vista(self, requisicion=None):
        build_crear_vista(self, requisicion)

    def _abrir_buscador_productos(self):
        build_buscador_productos(self)

    def _buscar_productos_buscador(self, texto, container):
        db = next(get_db_adaptive())
        try:
            query = db.query(Producto).filter(Producto.activo == True)
            if texto:
                query = query.filter(Producto.nombre.ilike(f"%{texto}%"))
            resultados = query.limit(30).all()
        finally:
            db.close()

        colors = _colors(self.page)
        container.controls.clear()

        for p in resultados:
            container.controls.append(build_producto_busqueda_item(p, self._agregar_producto_req, colors))

        if not resultados and texto:
            container.controls.append(
                ft.Text("Sin resultados", color=colors['text_secondary'], text_align="center")
            )

        container.update()

    def _agregar_producto_req(self, producto):
        db = next(get_db_adaptive())
        try:
            almacen_origen = getattr(self, '_origen_dropdown', None)
            origen = almacen_origen.value if almacen_origen else "principal"
            exist = db.query(Existencia).filter(
                Existencia.producto_id == producto.id,
                Existencia.almacen == origen,
            ).first()
            disponible = exist.cantidad if exist else 0
        finally:
            db.close()
        build_agregar_producto_req_dialog(self, producto, disponible)

    def _actualizar_lista_productos(self):
        colors = _colors(self.page)
        if self._productos_lista_req is None:
            return
        self._productos_lista_req.controls.clear()

        if not self.lista_productos_req:
            self._productos_lista_req.controls.append(
                ft.Container(
                    content=ft.Column([
                        ft.Icon(ft.Icons.CHAT_BUBBLE_OUTLINE, size=40, color=colors['text_hint']),
                        ft.Text("Toca + para agregar productos", color=colors['text_secondary'], text_align="center"),
                    ], horizontal_alignment="center", spacing=10),
                    alignment=ft.alignment.center,
                    expand=True,
                )
            )
        else:
            for i, item in enumerate(self.lista_productos_req):
                es_pesable = item.get('es_pesable', False)
                peso = item.get('peso', 0) or 0

                if es_pesable:
                    subtitulo = f"{peso:.2f} kg" if peso else f"{item['cantidad']} {item['unidad']}"
                else:
                    subtitulo = f"{item['cantidad']} {item['unidad']}"

                self._productos_lista_req.controls.append(
                    ft.Container(
                        content=ft.Row([
                            ft.Icon(ft.Icons.INVENTORY_2_OUTLINED, size=18, color=colors['accent']),
                            ft.Column([
                                ft.Text(item['nombre'], weight="bold", color=colors['text_primary'], size=13),
                                ft.Text(subtitulo, color=colors['text_secondary'], size=11),
                            ], expand=True, spacing=2),
                            ft.IconButton(
                                ft.Icons.CLOSE,
                                icon_size=18,
                                icon_color=colors['error'],
                                tooltip="Quitar",
                                on_click=lambda _, idx=i: self._eliminar_producto_req(idx),
                            ),
                        ], spacing=10, vertical_alignment="center"),
                        padding=ft.padding.symmetric(horizontal=12, vertical=6),
                        bgcolor=colors['card'],
                        border_radius=8,
                        margin=ft.margin.only(bottom=4),
                    )
                )

        if getattr(self._productos_lista_req, 'page', None) is not None:
            self._productos_lista_req.update()
            if self.lista_productos_req:
                try:
                    self._productos_lista_req.scroll_to(offset=-1, duration=150)
                except Exception:
                    pass

    def _eliminar_producto_req(self, idx):
        if idx < len(self.lista_productos_req):
            self.lista_productos_req.pop(idx)
            self._actualizar_lista_productos()

    def _crear_requisicion_vista(self, origen_dropdown, destino_dropdown, observaciones):
        if not self.lista_productos_req:
            show_warning("Agregue al menos un producto")
            return

        origen = origen_dropdown.value or "principal"
        destino = destino_dropdown.value or "restaurante"
        user_id = (self.page.session.get("user_id") or "Admin") if self.page else "Admin"

        req_editando = getattr(self, '_requisicion_editando', None)
        try:
            if req_editando:
                guardar_requisicion(
                    origen=origen, destino=destino,
                    observaciones=observaciones.value or "",
                    detalles=self.lista_productos_req,
                    editando=req_editando, user_id=user_id,
                )
                show_success("Requisición actualizada")
            else:
                guardar_requisicion(
                    origen=origen, destino=destino,
                    observaciones=observaciones.value or "",
                    detalles=self.lista_productos_req,
                    user_id=user_id, estado="pendiente", mover_stock=False,
                )
                show_success(f"Requisición creada: {origen} → {destino}")

            import threading
            try:
                from usr.database import get_sync_manager
                sync_mgr = get_sync_manager()
                if sync_mgr:
                    threading.Thread(target=sync_mgr.force_sync_now, daemon=True).start()
            except Exception:
                pass

            self.lista_productos_req = []
            self._requisicion_editando = None
            self._volver_lista()

        except Exception as ex:
            logger.error(f"Error guardando requisición: {ex}")
            show_error(f"Error: {ex}")

    def _volver_lista(self):
        self._vista_actual = "lista"
        self.lista_productos_req = []
        self._build_ui()
        self.update()
