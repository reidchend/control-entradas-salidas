import flet as ft
from datetime import datetime
from usr.database.base import get_db
from usr.models import Requisicion, RequisicionDetalle, Producto, Existencia
import logging
from usr.theme import get_theme

logger = logging.getLogger(__name__)


def _colors(page):
    if page and hasattr(page, 'theme_mode'):
        return get_theme(page.theme_mode == ft.ThemeMode.DARK)
    return get_theme(True)


def _get_color(page, color_name):
    """Obtiene color dinámico desde constantes de ft.Colors"""
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
    """Alias corto para _get_color"""
    return _get_color(page, color_name)


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
        
        self._build_ui()

    def on_theme_change(self):
        """Se llama cuando cambia el tema"""
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
                    on_click=lambda _: self._show_crear_dialog(),
                    tooltip="Nueva requisición",
                ),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            padding=ft.padding.only(left=20, right=20, top=20, bottom=10),
            bgcolor=colors['surface'],
        )
        
        self.content = ft.Column([
            header,
            self.requisiciones_list,
        ], expand=True, spacing=0)
        
        self._load_requisiciones()

    def did_mount(self):
        self._load_requisiciones()

    def _load_requisiciones(self):
        db = next(get_db())
        try:
            reqs = db.query(Requisicion).order_by(Requisicion.fecha_creacion.desc()).all()
            self.requisiciones_list.controls.clear()
            
            if not reqs:
                colors = _colors(self.page)
                self.requisiciones_list.controls.append(
                    ft.Container(
                        content=ft.Column([
                            ft.Icon(ft.Icons.INVENTORY_2_OUTLINED, size=50, color=colors['text_hint']),
                            ft.Text("No hay requisiciones", color=colors['text_secondary']),
                            ft.Text("Crea una nueva para comenzar", size=12, color=colors['text_secondary']),
                        ], horizontal_alignment="center"),
                        padding=ft.padding.only(top=80),
                        alignment=ft.alignment.top_center,
                    )
                )
            else:
                for req in reqs:
                    self.requisiciones_list.controls.append(self._create_requisicion_card(req))
            
            if self.page:
                self.page.update()
        except Exception as e:
            logger.error(f"Error cargando requisiciones: {e}")
        finally:
            db.close()

    def _create_requisicion_card(self, req: Requisicion):
        colors = _colors(self.page)
        estado_colors_map = {
            "pendiente": colors['warning'],
            "completada": colors['success'],
            "cancelada": colors['error'],
        }
        estado_color = estado_colors_map.get(req.estado, colors['text_secondary'])
        
        db = next(get_db())
        try:
            total_items = db.query(RequisicionDetalle).filter(
                RequisicionDetalle.requisicion_id == req.id
            ).count()
        finally:
            db.close()
        
        card = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(
                        content=ft.Icon(ft.Icons.ASSIGNMENT_ROUNDED, size=24, color=colors['white']),
                        bgcolor=colors['accent'],
                        width=44, height=44, border_radius=10,
                        alignment=ft.alignment.center,
                    ),
                    ft.Column([
                        ft.Text(f"#{req.numero}", weight="bold", size=16, color=colors['text_primary']),
                        ft.Row([
                            ft.Text(f"{req.origen} → {req.destino}", size=12, color=colors['text_secondary']),
                        ], spacing=5),
                    ], expand=True),
                    ft.Column([
                        ft.Container(
                            content=ft.Text(req.estado.upper(), size=10, weight="bold", color=colors['white']),
                            bgcolor=estado_color, padding=ft.padding.symmetric(horizontal=8, vertical=4),
                            border_radius=5,
                        ),
                        ft.Text(f"{total_items} items", size=11, color=colors['text_secondary']),
                    ], horizontal_alignment="center"),
                ]),
                ft.Divider(height=1, color=colors['border']),
                ft.Row([
                    ft.Text(f"Creada: {req.fecha_creacion.strftime('%d/%m/%Y %H:%M') if req.fecha_creacion else '-'}", 
                            size=11, color=colors['text_secondary'], expand=True),
                    ft.Row([
                        ft.TextButton("Ver", on_click=lambda _, r=req: self._show_detalles(r)),
                        ft.TextButton("Editar", on_click=lambda _, r=req: self._editar_requisicion(r)),
                    ], spacing=5),
                ]),
            ], spacing=8),
            padding=15,
            bgcolor=colors['card'],
            border_radius=12,
            border=ft.border.all(1, _c(self.page, 'GREY_200')),
            on_click=lambda _, r=req: self._show_detalles(r),
        )
        return card

    def _show_crear_dialog(self):
        self.detalles_temp = []
        
        numero_input = ft.TextField(
            label="Número de requisición",
            hint_text="REQ-001",
            border_radius=10,
            autofocus=True,
        )
        
        db = next(get_db())
        try:
            almacenes = db.query(Existencia.almacen).distinct().all()
            opciones_almacen = [a[0] for a in almacenes]
            if "principal" not in opciones_almacen:
                opciones_almacen.append("principal")
            
            productos = db.query(Producto).filter(Producto.activo == True).order_by(Producto.nombre).limit(200).all()
            self._productos_cache = productos
        finally:
            db.close()
        
        origen_dropdown = ft.Dropdown(
            label="Almacén Origen",
            options=[ft.dropdown.Option(a, a.capitalize()) for a in opciones_almacen],
            value="principal",
            border_radius=10,
        )
        
        destino_dropdown = ft.Dropdown(
            label="Almacén Destino",
            options=[ft.dropdown.Option(a, a.capitalize()) for a in opciones_almacen],
            value="restaurante",
            border_radius=10,
        )
        
        observaciones_input = ft.TextField(
            label="Observaciones",
            hint_text="Notas adicionales...",
            border_radius=10,
            multiline=True,
            min_lines=2,
        )
        
        productos_container = ft.Column([], spacing=5)
        
        # Barra de búsqueda de productos
        busqueda_input = ft.TextField(
            label="Buscar producto",
            hint_text="Escribe para buscar...",
            border_radius=10,
            prefix_icon=ft.Icons.SEARCH,
            on_change=lambda e: self._filtrar_productos_busqueda(e.control.value, resultados_container),
        )
        
        resultados_container = ft.Column([], spacing=5)
        
        def agregar_producto_rapido(producto, cantidad):
            for fila in productos_container.controls:
                prod_drop = fila.controls[0]
                if prod_drop.value == str(producto.id):
                    cant_input = fila.controls[1]
                    try:
                        cant_input.value = str(float(cant_input.value or "0") + cantidad)
                        cant_input.update()
                    except:
                        pass
                    return
            
            cant_input = ft.TextField(
                label="Cantidad",
                value=str(cantidad),
                keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10,
                width=100,
            )
            unidad_input = ft.TextField(
                label="Unidad",
                value=producto.unidad_medida or "unidad",
                border_radius=10,
                width=100,
            )
            
            prod_label = ft.Text(
                producto.nombre,
                size=14,
                weight="bold",
                color=_c(self.page, 'BLUE_GREY_800'),
            )
            
            delete_btn = ft.IconButton(
                ft.Icons.DELETE_ROUNDED, 
                icon_color=colors['error'], 
                on_click=lambda _, dbtn=delete_btn: self._eliminar_producto_row(dbtn, productos_container)
            )
            
            fila = ft.Row([
                prod_label,
                cant_input,
                unidad_input,
                delete_btn,
            ], spacing=10)
            
            productos_container.controls.append(fila)
            productos_container.update()
        
        def on_agregar_click(producto):
            agregar_producto_rapido(producto, 1)
            busqueda_input.value = ""
            resultados_container.controls.clear()
            resultados_container.update()
        
        self._on_agregar_producto = on_agregar_click
        self._resultados_container = resultados_container
        
        agregar_btn = ft.ElevatedButton(
            "Agregar Producto",
            icon=ft.Icons.ADD,
            on_click=lambda _: self._show_agregar_producto_dialog(productos_container),
        )
        
        def on_confirmar(e):
            if not numero_input.value:
                numero_input.error_text = "Requerido"
                numero_input.update()
                return
            
            db = next(get_db())
            try:
                detalles = []
                for fila in productos_container.controls:
                    prod_dropdown = fila.controls[0]
                    cant_input = fila.controls[1]
                    unidad_input = fila.controls[2]
                    
                    if prod_dropdown.value and cant_input.value:
                        try:
                            cantidad = float(cant_input.value.replace(",", ""))
                            producto_id = int(prod_dropdown.value)
                            producto = db.query(Producto).filter(Producto.id == producto_id).first()
                            
                            detalles.append({
                                "producto_id": producto_id,
                                "ingrediente": producto.nombre if producto else "Desconocido",
                                "cantidad": cantidad,
                                "unidad": unidad_input.value or "unidad",
                            })
                        except ValueError:
                            pass
                
                req = Requisicion(
                    numero=numero_input.value,
                    origen=origen_dropdown.value or "principal",
                    destino=destino_dropdown.value or "restaurante",
                    estado="pendiente",
                    observaciones=observaciones_input.value,
                    creada_por=self.page.session.get("user_id") or "Admin",
                )
                db.add(req)
                db.flush()
                
                for d in detalles:
                    detalle = RequisicionDetalle(
                        requisicion_id=req.id,
                        producto_id=d["producto_id"],
                        ingrediente=d["ingrediente"],
                        cantidad=d["cantidad"],
                        unidad=d["unidad"],
                    )
                    db.add(detalle)
                
                db.commit()
                self.active_dialog.open = False
                self.page.update()
                self._load_requisiciones()
                
                snack = ft.SnackBar(content=ft.Text(f"✓ Requisición #{req.numero} creada"), bgcolor=colors['success'])
                self.page.overlay.append(snack)
                snack.open = True
                self.page.update()
            except Exception as ex:
                db.rollback()
                logger.error(f"Error creando requisición: {ex}")
                snack = ft.SnackBar(content=ft.Text(f"Error: {ex}"), bgcolor=colors['error'])
                self.page.overlay.append(snack)
                snack.open = True
                self.page.update()
            finally:
                db.close()
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Text("Nueva Requisición"),
            content=ft.Column([
                numero_input,
                ft.Row([origen_dropdown, destino_dropdown], spacing=15),
                observaciones_input,
                ft.Divider(),
                ft.Text("Productos:", weight="bold"),
                productos_container,
                agregar_btn,
            ], tight=True, spacing=10, scroll=ft.ScrollMode.AUTO),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Crear", on_click=on_confirmar, bgcolor=colors['accent'], color="white"),
            ],
        )
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _eliminar_producto(self, fila, container):
        container.controls.remove(fila)
        container.update()

    def _eliminar_producto_row(self, btn, container):
        for fila in container.controls:
            if btn in fila.controls:
                container.controls.remove(fila)
                container.update()
                break

    def _editar_requisicion(self, req: Requisicion):
        if req.estado == "completada":
            snack = ft.SnackBar(content=ft.Text("No se puede editar una requisición completada"), bgcolor=colors['warning'])
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            return
        
        if self.app_controller and self.inventario_view:
            self.app_controller._show_view(0)
            self.inventario_view._show_panel_requisicion(req)
            return

    def _show_agregar_producto_dialog(self, productos_container):
        db = next(get_db())
        try:
            productos = db.query(Producto).filter(Producto.activo == True).order_by(Producto.nombre).limit(200).all()
        finally:
            db.close()
        
        resultados_container = ft.Column([], spacing=5, scroll=ft.ScrollMode.AUTO)
        
        busqueda_input = ft.TextField(
            label="Buscar producto",
            hint_text="Escribe el nombre del producto...",
            border_radius=10,
            prefix_icon=ft.Icons.SEARCH,
            autofocus=True,
            on_change=lambda e: self._filtrar_productos_busqueda(e.control.value, productos, resultados_container),
        )
        
        def agregar_producto(producto):
            cantidad_input = ft.TextField(
                label="Cantidad",
                value="1",
                keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10,
                width=100,
            )
            
            unidad_input = ft.TextField(
                label="Unidad",
                value=producto.unidad_medida or "unidad",
                border_radius=10,
                width=100,
            )
            
            prod_label = ft.Text(
                producto.nombre,
                size=14,
                expand=True,
            )
            
            delete_btn = ft.IconButton(
                ft.Icons.DELETE_ROUNDED, 
                icon_color=colors['error'], 
            )
            
            fila = ft.Row([
                prod_label,
                cantidad_input,
                unidad_input,
                delete_btn,
            ], spacing=10)
            
            def eliminar():
                productos_container.controls.remove(fila)
                productos_container.update()
            
            delete_btn.on_click = lambda _, dbtn=delete_btn: eliminar()
            
            productos_container.controls.append(fila)
            productos_container.update()
            
            dialog.open = False
            self.page.update()
        
        def crear_item_producto(producto):
            return ft.Container(
                content=ft.Row([
                    ft.Column([
                        ft.Text(producto.nombre, weight="bold", size=14),
                        ft.Text(f"Unidad: {producto.unidad_medida or 'unidad'}", size=11, color=colors['text_secondary']),
                    ], expand=True),
                    ft.IconButton(ft.Icons.ADD_CIRCLE, icon_color=colors['success'], 
                                  on_click=lambda _, p=producto: agregar_producto(p)),
                ]),
                padding=10,
                bgcolor=colors['bg'],
                border_radius=8,
                on_click=lambda _, p=producto: agregar_producto(p),
            )
        
        lista_productos = ft.Column([
            crear_item_producto(p) for p in productos[:20]
        ], spacing=5, scroll=ft.ScrollMode.AUTO)
        
        resultados_container.content = lista_productos
        
        dialog = ft.AlertDialog(
            title=ft.Text("Agregar Producto"),
            content=ft.Column([
                busqueda_input,
                ft.Container(height=10),
                ft.Container(
                    content=resultados_container,
                    bgcolor=colors['card'],
                    border_radius=10,
                    border=ft.border.all(1, _c(self.page, 'GREY_300')),
                    padding=5,
                ),
            ], tight=True, scroll=ft.ScrollMode.AUTO),
            actions=[
                ft.TextButton("Cerrar", on_click=lambda _: self._cerrar_dialog(dialog)),
            ],
        )
        
        self.page.overlay.append(dialog)
        dialog.open = True
        self.page.update()

    def _filtrar_productos_busqueda(self, texto, productos, container):
        container.controls.clear()
        
        if not texto or len(texto) < 1:
            for p in productos[:20]:
                container.controls.append(self._crear_item_producto_busqueda(p))
        else:
            texto_lower = texto.lower()
            filtrados = [p for p in productos if texto_lower in p.nombre.lower()]
            for p in filtrados[:20]:
                container.controls.append(self._crear_item_producto_busqueda(p))
        
        container.update()

    def _crear_item_producto_busqueda(self, producto):
        def agregar():
            cantidad_input = ft.TextField(
                label="Cantidad",
                value="1",
                keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10,
                width=100,
            )
            
            unidad_input = ft.TextField(
                label="Unidad",
                value=producto.unidad_medida or "unidad",
                border_radius=10,
                width=100,
            )
            
            prod_label = ft.Text(producto.nombre, size=14, expand=True)
            
            delete_btn = ft.IconButton(ft.Icons.DELETE_ROUNDED, icon_color=colors['error'])
            
            fila = ft.Row([prod_label, cantidad_input, unidad_input, delete_btn], spacing=10)
            
            def eliminar():
                if hasattr(self, '_productos_temp_container'):
                    self._productos_temp_container.controls.remove(fila)
                    self._productos_temp_container.update()
            
            delete_btn.on_click = lambda _, dbtn=delete_btn: eliminar()
            
            if hasattr(self, '_productos_temp_container'):
                self._productos_temp_container.controls.append(fila)
                self._productos_temp_container.update()
            
            self._productos_temp_dialog.open = False
            self.page.update()
        
        return ft.Container(
            content=ft.Row([
                ft.Text(producto.nombre, weight="bold", size=14, expand=True),
                ft.IconButton(ft.Icons.ADD_CIRCLE, icon_color=colors['success'], on_click=lambda _: agregar()),
            ]),
            padding=10,
            bgcolor=colors['bg'],
            border_radius=8,
            on_click=lambda _: agregar(),
        )

    def _cerrar_dialog(self, dialog):
        dialog.open = False
        self.page.update()

    def _close_dialog(self):
        if self.active_dialog:
            self.active_dialog.open = False
            self.page.update()

    def _show_detalles(self, req: Requisicion):
        db = next(get_db())
        try:
            detalles = db.query(RequisicionDetalle).filter(
                RequisicionDetalle.requisicion_id == req.id
            ).all()
            
            content = ft.Column(spacing=8, scroll=ft.ScrollMode.AUTO)
            
            for d in detalles:
                content.controls.append(
                    ft.Container(
                        content=ft.Row([
                            ft.Text(d.ingrediente, weight="bold", expand=True),
                            ft.Text(f"{d.cantidad:.2f} {d.unidad}", color=colors['accent']),
                        ]),
                        padding=10,
                        bgcolor=colors['bg'],
                        border_radius=8,
                    )
                )
            
            if not detalles:
                content.controls.append(
                    ft.Text("No hay productos en esta requisición", color=colors['text_secondary'])
                )
            
            dialog = ft.AlertDialog(
                title=ft.Text(f"Requisición #{req.numero}"),
                content=ft.Column([
                    ft.Row([
                        ft.Container(
                            content=ft.Column([
                                ft.Text("Origen", size=11, color=colors['text_secondary']),
                                ft.Text(req.origen.capitalize(), weight="bold"),
                            ], spacing=2),
                        ),
                        ft.Icon(ft.Icons.ARROW_FORWARD, color=_c(self.page, 'GREY_400')),
                        ft.Container(
                            content=ft.Column([
                                ft.Text("Destino", size=11, color=colors['text_secondary']),
                                ft.Text(req.destino.capitalize(), weight="bold"),
                            ], spacing=2),
                        ),
                    ], spacing=20),
                    ft.Divider(),
                    ft.Text("Productos:", weight="bold"),
                    content,
                    ft.Divider(),
                    ft.Text(f"Estado: {req.estado.upper()}", weight="bold", color=colors['accent']),
                    ft.Text(f"Creada: {req.fecha_creacion.strftime('%d/%m/%Y %H:%M') if req.fecha_creacion else '-'}", size=11, color=colors['text_secondary']),
                    ft.Text(f"Observaciones: {req.observaciones or 'Sin observaciones'}", size=11, color=colors['text_secondary']),
                ], tight=True, spacing=10),
                actions=[
                    ft.TextButton("Cerrar", on_click=lambda _: self._close_dialog()),
                ],
            )
            
            self.active_dialog = dialog
            self.page.overlay.append(dialog)
            dialog.open = True
            self.page.update()
        except Exception as ex:
            logger.error(f"Error mostrando detalles: {ex}")
        finally:
            db.close()
