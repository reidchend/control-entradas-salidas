import flet as ft
import json
from datetime import datetime
from usr.database.base import get_db
from usr.models import Requisicion, RequisicionDetalle, Producto, Existencia
import logging

logger = logging.getLogger(__name__)


class RequisicionesView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.bgcolor = ft.Colors.GREY_50
        self.padding = 0
        
        self.requisiciones_list = ft.ListView(expand=True, spacing=10, padding=20)
        self.detalles_temp = []
        self.active_dialog = None
        self.inventario_view = None
        self.app_controller = None
        
        self._build_ui()

    def _build_ui(self):
        header = ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Text("Requisiciones", size=26, weight="bold", color=ft.Colors.BLUE_GREY_900),
                    ft.Text("Gestión de traslados", size=13, color=ft.Colors.BLUE_GREY_400),
                ], expand=True, spacing=0),
                ft.IconButton(
                    ft.Icons.ADD_ROUNDED,
                    icon_color=ft.Colors.WHITE,
                    bgcolor=ft.Colors.BLUE_600,
                    on_click=lambda _: self._show_crear_dialog(),
                    tooltip="Nueva requisición",
                ),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            padding=ft.padding.only(left=20, right=20, top=20, bottom=10),
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
                self.requisiciones_list.controls.append(
                    ft.Container(
                        content=ft.Column([
                            ft.Icon(ft.Icons.INVENTORY_2_OUTLINED, size=50, color=ft.Colors.GREY_300),
                            ft.Text("No hay requisiciones", color=ft.Colors.GREY_400),
                            ft.Text("Crea una nueva para comenzar", size=12, color=ft.Colors.GREY_400),
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
        estado_colors = {
            "pendiente": ft.Colors.ORANGE_600,
            "completada": ft.Colors.GREEN_600,
            "cancelada": ft.Colors.RED_600,
        }
        estado_color = estado_colors.get(req.estado, ft.Colors.GREY_600)
        
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
                        content=ft.Icon(ft.Icons.ASSIGNMENT_ROUNDED, size=24, color=ft.Colors.WHITE),
                        bgcolor=ft.Colors.BLUE_600,
                        width=44, height=44, border_radius=10,
                        alignment=ft.alignment.center,
                    ),
                    ft.Column([
                        ft.Text(f"#{req.numero}", weight="bold", size=16, color=ft.Colors.BLUE_GREY_900),
                        ft.Row([
                            ft.Text(f"{req.origen} → {req.destino}", size=12, color=ft.Colors.BLUE_GREY_500),
                        ], spacing=5),
                    ], expand=True),
                    ft.Column([
                        ft.Container(
                            content=ft.Text(req.estado.upper(), size=10, weight="bold", color="white"),
                            bgcolor=estado_color, padding=ft.padding.symmetric(horizontal=8, vertical=4),
                            border_radius=5,
                        ),
                        ft.Text(f"{total_items} items", size=11, color=ft.Colors.GREY_500),
                    ], horizontal_alignment="center"),
                ]),
                ft.Divider(height=1, color=ft.Colors.GREY_200),
                ft.Row([
                    ft.Text(f"Creada: {req.fecha_creacion.strftime('%d/%m/%Y %H:%M') if req.fecha_creacion else '-'}", 
                            size=11, color=ft.Colors.GREY_500, expand=True),
                    ft.Row([
                        ft.TextButton("Ver", on_click=lambda _, r=req: self._show_detalles(r)),
                        ft.TextButton("Editar", on_click=lambda _, r=req: self._editar_requisicion(r)),
                        ft.TextButton("Exportar", on_click=lambda _, r=req: self._exportar_requisicion(r)),
                    ], spacing=5),
                ]),
            ], spacing=8),
            padding=15,
            bgcolor=ft.Colors.WHITE,
            border_radius=12,
            border=ft.border.all(1, ft.Colors.GREY_200),
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
                color=ft.Colors.BLUE_GREY_800,
            )
            
            delete_btn = ft.IconButton(
                ft.Icons.DELETE_ROUNDED, 
                icon_color=ft.Colors.RED_400, 
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
                
                snack = ft.SnackBar(content=ft.Text(f"✓ Requisición #{req.numero} creada"), bgcolor=ft.Colors.GREEN_700)
                self.page.overlay.append(snack)
                snack.open = True
                self.page.update()
            except Exception as ex:
                db.rollback()
                logger.error(f"Error creando requisición: {ex}")
                snack = ft.SnackBar(content=ft.Text(f"Error: {ex}"), bgcolor=ft.Colors.RED_700)
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
                ft.ElevatedButton("Crear", on_click=on_confirmar, bgcolor=ft.Colors.BLUE_600, color="white"),
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
            snack = ft.SnackBar(content=ft.Text("No se puede editar una requisición completada"), bgcolor=ft.Colors.ORANGE_700)
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            return
        
        if self.app_controller and self.inventario_view:
            self.app_controller._show_view(0)
            self.inventario_view._show_panel_requisicion(req)
            return
        
        db = next(get_db())
        try:
            detalles = db.query(RequisicionDetalle).filter(
                RequisicionDetalle.requisicion_id == req.id
            ).all()
            
            productos_db = db.query(Producto).filter(Producto.activo == True).order_by(Producto.nombre).limit(200).all()
            almacenes = db.query(Existencia.almacen).distinct().all()
            opciones_almacen = [a[0] for a in almacenes]
            if "principal" not in opciones_almacen:
                opciones_almacen.append("principal")
        finally:
            db.close()
        
        numero_input = ft.TextField(
            label="Número de requisición",
            value=req.numero,
            border_radius=10,
        )
        
        origen_dropdown = ft.Dropdown(
            label="Almacén Origen",
            options=[ft.dropdown.Option(a, a.capitalize()) for a in opciones_almacen],
            value=req.origen,
            border_radius=10,
        )
        
        destino_dropdown = ft.Dropdown(
            label="Almacén Destino",
            options=[ft.dropdown.Option(a, a.capitalize()) for a in opciones_almacen],
            value=req.destino,
            border_radius=10,
        )
        
        observaciones_input = ft.TextField(
            label="Observaciones",
            value=req.observaciones or "",
            border_radius=10,
            multiline=True,
            min_lines=2,
        )
        
        productos_container = ft.Column([], spacing=5)
        
        for d in detalles:
            cantidad_input = ft.TextField(
                label="Cantidad",
                value=str(d.cantidad),
                keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10,
                width=100,
            )
            unidad_input = ft.TextField(
                label="Unidad",
                value=d.unidad,
                border_radius=10,
                width=100,
            )
            prod_label = ft.Text(d.ingrediente, size=14, expand=True)
            delete_btn = ft.IconButton(
                ft.Icons.DELETE_ROUNDED, 
                icon_color=ft.Colors.RED_400,
            )
            
            fila = ft.Row([prod_label, cantidad_input, unidad_input, delete_btn], spacing=10)
            
            def eliminar():
                productos_container.controls.remove(fila)
                productos_container.update()
            
            delete_btn.on_click = lambda _, dbtn=delete_btn: eliminar()
            
            productos_container.controls.append(fila)
        
        agregar_btn = ft.ElevatedButton(
            "Agregar Producto",
            icon=ft.Icons.ADD,
            on_click=lambda _: self._show_agregar_producto_dialog_editar(productos_container, productos_db),
        )
        
        def on_guardar(e):
            db = next(get_db())
            try:
                req.numero = numero_input.value
                req.origen = origen_dropdown.value
                req.destino = destino_dropdown.value
                req.observaciones = observaciones_input.value
                
                for fila in productos_container.controls:
                    cantidad_input = fila.controls[1]
                    unidad_input = fila.controls[2]
                    prod_label = fila.controls[0]
                    
                    try:
                        cantidad = float(cantidad_input.value.replace(",", ""))
                    except:
                        cantidad = 0
                    
                    producto = None
                    for p in productos_db:
                        if p.nombre == prod_label.value:
                            producto = p
                            break
                    
                    detalle_existente = next((d for d in detalles if d.ingrediente == prod_label.value), None)
                    
                    if detalle_existente:
                        detalle_existente.cantidad = cantidad
                        detalle_existente.unidad = unidad_input.value or "unidad"
                    elif producto and cantidad > 0:
                        nuevo_detalle = RequisicionDetalle(
                            requisicion_id=req.id,
                            producto_id=producto.id,
                            ingrediente=prod_label.value,
                            cantidad=cantidad,
                            unidad=unidad_input.value or "unidad",
                        )
                        db.add(nuevo_detalle)
                
                db.commit()
                self.active_dialog.open = False
                self.page.update()
                self._load_requisiciones()
                
                snack = ft.SnackBar(content=ft.Text(f"✓ Requisición #{req.numero} actualizada"), bgcolor=ft.Colors.GREEN_700)
                self.page.overlay.append(snack)
                snack.open = True
                self.page.update()
            except Exception as ex:
                db.rollback()
                snack = ft.SnackBar(content=ft.Text(f"Error: {ex}"), bgcolor=ft.Colors.RED_700)
                self.page.overlay.append(snack)
                snack.open = True
                self.page.update()
            finally:
                db.close()
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Text(f"Editar Requisición #{req.numero}"),
            content=ft.Column([
                numero_input,
                ft.Row([origen_dropdown, destino_dropdown], spacing=15),
                observaciones_input,
                ft.Divider(),
                ft.Text("Productos:", weight="bold"),
                ft.Container(
                    content=productos_container,
                    bgcolor=ft.Colors.WHITE,
                    border_radius=10,
                    padding=10,
                    border=ft.border.all(1, ft.Colors.GREY_300),
                    height=300,
                ),
                agregar_btn,
            ], tight=True, spacing=10, scroll=ft.ScrollMode.AUTO),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Guardar", on_click=on_guardar, bgcolor=ft.Colors.BLUE_600, color="white"),
            ],
        )
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _show_agregar_producto_dialog_editar(self, productos_container, productos):
        resultados_container = ft.Column([], spacing=5, scroll=ft.ScrollMode.AUTO)
        
        busqueda_input = ft.TextField(
            label="Buscar producto",
            hint_text="Escribe el nombre del producto...",
            border_radius=10,
            prefix_icon=ft.Icons.SEARCH,
            autofocus=True,
            on_change=lambda e: self._filtrar_productos_busqueda_editar(e.control.value, productos, resultados_container, productos_container),
        )
        
        lista_inicial = ft.Column([
            self._crear_item_producto_editar(p, productos_container, resultados_container) for p in productos[:20]
        ], spacing=5, scroll=ft.ScrollMode.AUTO)
        
        resultados_container.content = lista_inicial
        
        dialog = ft.AlertDialog(
            title=ft.Text("Agregar Producto"),
            content=ft.Column([
                busqueda_input,
                ft.Container(height=10),
                ft.Container(
                    content=resultados_container,
                    bgcolor=ft.Colors.WHITE,
                    border_radius=10,
                    border=ft.border.all(1, ft.Colors.GREY_300),
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

    def _filtrar_productos_busqueda_editar(self, texto, productos, container, productos_container):
        if container.content:
            container.content.controls.clear()
        else:
            container.content = ft.Column([], spacing=5)
        
        if not texto or len(texto) < 1:
            for p in productos[:20]:
                container.content.controls.append(self._crear_item_producto_editar(p, productos_container, container))
        else:
            texto_lower = texto.lower()
            filtrados = [p for p in productos if texto_lower in p.nombre.lower()]
            for p in filtrados[:20]:
                container.content.controls.append(self._crear_item_producto_editar(p, productos_container, container))
        
        container.update()

    def _crear_item_producto_editar(self, producto, productos_container, resultados_container):
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
            delete_btn = ft.IconButton(ft.Icons.DELETE_ROUNDED, icon_color=ft.Colors.RED_400)
            
            fila = ft.Row([prod_label, cantidad_input, unidad_input, delete_btn], spacing=10)
            
            def eliminar():
                productos_container.controls.remove(fila)
                productos_container.update()
            
            delete_btn.on_click = lambda _, dbtn=delete_btn: eliminar()
            
            productos_container.controls.append(fila)
            productos_container.update()
            
            resultados_container.open = False
            self.page.update()
        
        return ft.Container(
            content=ft.Row([
                ft.Text(producto.nombre, weight="bold", size=14, expand=True),
                ft.IconButton(ft.Icons.ADD_CIRCLE, icon_color=ft.Colors.GREEN_600, on_click=lambda _: agregar()),
            ]),
            padding=10,
            bgcolor=ft.Colors.GREY_50,
            border_radius=8,
            on_click=lambda _: agregar(),
        )

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
                icon_color=ft.Colors.RED_400, 
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
                        ft.Text(f"Unidad: {producto.unidad_medida or 'unidad'}", size=11, color=ft.Colors.GREY_500),
                    ], expand=True),
                    ft.IconButton(ft.Icons.ADD_CIRCLE, icon_color=ft.Colors.GREEN_600, 
                                  on_click=lambda _, p=producto: agregar_producto(p)),
                ]),
                padding=10,
                bgcolor=ft.Colors.GREY_50,
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
                    bgcolor=ft.Colors.WHITE,
                    border_radius=10,
                    border=ft.border.all(1, ft.Colors.GREY_300),
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
            
            delete_btn = ft.IconButton(ft.Icons.DELETE_ROUNDED, icon_color=ft.Colors.RED_400)
            
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
                ft.IconButton(ft.Icons.ADD_CIRCLE, icon_color=ft.Colors.GREEN_600, on_click=lambda _: agregar()),
            ]),
            padding=10,
            bgcolor=ft.Colors.GREY_50,
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
                            ft.Text(f"{d.cantidad:.2f} {d.unidad}", color=ft.Colors.BLUE_700),
                        ]),
                        padding=10,
                        bgcolor=ft.Colors.GREY_50,
                        border_radius=8,
                    )
                )
            
            if not detalles:
                content.controls.append(
                    ft.Text("No hay productos en esta requisición", color=ft.Colors.GREY_500)
                )
            
            dialog = ft.AlertDialog(
                title=ft.Text(f"Requisición #{req.numero}"),
                content=ft.Column([
                    ft.Row([
                        ft.Container(
                            content=ft.Column([
                                ft.Text("Origen", size=11, color=ft.Colors.GREY_500),
                                ft.Text(req.origen.capitalize(), weight="bold"),
                            ], spacing=2),
                        ),
                        ft.Icon(ft.Icons.ARROW_FORWARD, color=ft.Colors.GREY_400),
                        ft.Container(
                            content=ft.Column([
                                ft.Text("Destino", size=11, color=ft.Colors.GREY_500),
                                ft.Text(req.destino.capitalize(), weight="bold"),
                            ], spacing=2),
                        ),
                    ], spacing=20),
                    ft.Divider(),
                    ft.Text("Productos:", weight="bold"),
                    content,
                    ft.Divider(),
                    ft.Text(f"Estado: {req.estado.upper()}", weight="bold", color=ft.Colors.BLUE_700),
                    ft.Text(f"Creada: {req.fecha_creacion.strftime('%d/%m/%Y %H:%M') if req.fecha_creacion else '-'}", size=11, color=ft.Colors.GREY_500),
                    ft.Text(f"Observaciones: {req.observaciones or 'Sin observaciones'}", size=11, color=ft.Colors.GREY_500),
                ], tight=True, spacing=10),
                actions=[
                    ft.TextButton("Cerrar", on_click=lambda _: self._close_dialog()),
                    ft.ElevatedButton("Exportar JSON", icon=ft.Icons.DOWNLOAD, 
                                     on_click=lambda _, r=req: self._exportar_requisicion(r)),
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

    def _exportar_requisicion(self, req: Requisicion):
        db = next(get_db())
        try:
            detalles = db.query(RequisicionDetalle).filter(
                RequisicionDetalle.requisicion_id == req.id
            ).all()
            
            data = {
                "requisicion": req.numero,
                "fecha": req.fecha_creacion.isoformat() if req.fecha_creacion else None,
                "origen": req.origen,
                "destino": req.destino,
                "estado": req.estado,
                "productos": [
                    {
                        "ingrediente": d.ingrediente,
                        "cantidad": d.cantidad,
                        "unidad": d.unidad,
                    }
                    for d in detalles
                ]
            }
            
            json_str = json.dumps(data, indent=2, ensure_ascii=False)
            
            req_data = ft.Container(
                content=ft.Column([
                    ft.Text("Archivo JSON exportado:", weight="bold"),
                    ft.Container(
                        content=ft.Text(json_str, size=10, font_family="monospace"),
                        bgcolor=ft.Colors.GREY_100,
                        padding=10,
                        border_radius=8,
                        height=300,
                    ),
                ], spacing=10),
                padding=10,
            )
            
            dialog = ft.AlertDialog(
                title=ft.Text(f"Exportar #{req.numero}"),
                content=req_data,
                actions=[
                    ft.TextButton("Cerrar", on_click=lambda _: self._close_dialog()),
                    ft.ElevatedButton(
                        "Copiar al Portapapeles",
                        icon=ft.Icons.COPY,
                        on_click=lambda _: self._copiar_portapapeles(json_str),
                    ),
                ],
            )
            
            self.active_dialog = dialog
            self.page.overlay.append(dialog)
            dialog.open = True
            self.page.update()
        except Exception as ex:
            logger.error(f"Error exportando: {ex}")
        finally:
            db.close()

    def _copiar_portapapeles(self, text):
        self.page.set_clipboard(text)
        snack = ft.SnackBar(content=ft.Text("✓ Copiado al portapapeles"), bgcolor=ft.Colors.GREEN_700)
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()
