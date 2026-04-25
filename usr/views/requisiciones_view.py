import warnings
warnings.filterwarnings("ignore", category=PendingDeprecationWarning)

import flet as ft
from datetime import datetime
from usr.database.base import get_db, get_db_adaptive
from usr.database.sync_callbacks import register_sync_callback, unregister_sync_callback
from usr.models import Requisicion, RequisicionDetalle, Producto, Existencia
import logging
from usr.theme import get_theme, get_colors

logger = logging.getLogger(__name__)


def _colors(page):
    return get_colors(page)


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
        self.app_controller: any = None
        
        self._vista_actual = "lista"  # lista | crear
        self.lista_productos_req = []
        
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
                    on_click=lambda _: self._show_crear_vista(),
                    tooltip="Nueva requisición",
                ),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            padding=ft.padding.only(left=20, right=20, top=20, bottom=10),
            bgcolor=colors['surface'],
        )
        
        # Corrección: Asegurar que el ListView esté dentro de algo que lo muestre
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
        
        # Test: Añadir algo visible si la lista está vacía
        self.requisiciones_list.controls.append(ft.Text("PRUEBA DE LISTA", color=ft.Colors.RED))
        
        self.update() 
        self._load_requisiciones()
    def did_mount(self):
        self._build_ui()
        register_sync_callback(self._on_sync_complete)
    
    def will_unmount(self):
        unregister_sync_callback(self._on_sync_complete)
    
    def _on_sync_complete(self):
        if hasattr(self, 'page') and self.page and self.visible:
            if self._vista_actual == "lista":
                self.page.run_task(self._load_requisiciones)
    
    def on_sync_complete(self):
        self._on_sync_complete()

    def _load_requisiciones(self):
        db = next(get_db_adaptive())
        try:
            reqs = db.query(Requisicion).order_by(Requisicion.fecha_creacion.desc()).all()
            
            # Limpiar y añadir algo fijo para probar renderizado
            self.requisiciones_list.controls.clear()
            self.requisiciones_list.controls.append(ft.Container(content=ft.Text("PRUEBA DE DATOS", color=ft.Colors.WHITE), bgcolor=ft.Colors.BLUE, padding=20))
            
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
                    self.requisiciones_list.controls.append(self._create_requisicion_card(req))
            
            # Forzar actualización de todos los niveles
            self.requisiciones_list.update()
            self.list_container.update()
            if self.page:
                self.page.update()
        except Exception as e:
            logger.error(f"Error cargando requisiciones: {e}")
        finally:
            db.close()

    def _create_requisicion_card(self, req: Requisicion):
        # Colores explícitos para evitar fallos de renderizado
        card_bg = '#2D2D2D'
        text_primary = ft.Colors.WHITE
        text_secondary = '#AAAAAA'
        
        estado_colors_map = {
            "pendiente": '#FF9800',
            "completada": '#4CAF50',
            "cancelada": '#F44336',
        }
        estado_color = estado_colors_map.get(req.estado, text_secondary)
        
        # Obtener total de items de forma segura
        total_items = 0
        try:
            db = next(get_db_adaptive())
            total_items = db.query(RequisicionDetalle).filter(
                RequisicionDetalle.requisicion_id == req.id
            ).count()
            db.close()
        except:
            pass
        
        # Construcción simplificada de la tarjeta
        return ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(
                        content=ft.Icon(ft.Icons.ASSIGNMENT_ROUNDED, size=24, color=ft.Colors.WHITE),
                        bgcolor=ft.Colors.DEEP_PURPLE_400,
                        width=44, height=44, border_radius=10,
                        alignment=ft.alignment.center,
                    ),
                    ft.Column([
                        ft.Text(f"#{req.numero}", weight="bold", size=16, color=text_primary),
                        ft.Text(f"{req.origen} → {req.destino}", size=12, color=text_secondary),
                    ], expand=True, spacing=0),
                    ft.Column([
                        ft.Container(
                            content=ft.Text(req.estado.upper(), size=10, weight="bold", color=ft.Colors.WHITE),
                            bgcolor=estado_color, padding=ft.padding.symmetric(horizontal=8, vertical=4),
                            border_radius=5,
                        ),
                        ft.Text(f"{total_items} items", size=11, color=text_secondary),
                    ], horizontal_alignment="center"),
                ]),
                ft.Divider(height=1, color='#3D3D3D'),
                ft.Row([
                    ft.Text(f"Creada: {req.fecha_creacion.strftime('%d/%m/%Y %H:%M') if req.fecha_creacion else '-'}", 
                            size=11, color=text_secondary, expand=True),
                    ft.Row([
                        ft.TextButton("Ver", on_click=lambda _: self._show_detalles(req)),
                        ft.TextButton("Editar", on_click=lambda _: self._editar_requisicion(req)),
                    ], spacing=5),
                ]),
            ], spacing=8),
            padding=15,
            bgcolor=card_bg,
            border_radius=12,
            border=ft.border.all(1, '#3D3D3D'),
            on_click=lambda _: self._show_detalles(req),
        )

    def _show_crear_dialog(self):
        colors = _colors(self.page)
        is_mobile = self.page.width < 700 if self.page else False
        self.detalles_temp = []
        
        db = next(get_db_adaptive())
        try:
            almacenes = db.query(Existencia.almacen).distinct().all()
            opciones_almacen = [a[0] for a in almacenes]
            if "principal" not in opciones_almacen:
                opciones_almacen.append("principal")
            if "restaurante" not in opciones_almacen:
                opciones_almacen.append("restaurante")
            
            productos = db.query(Producto).filter(Producto.activo == True).order_by(Producto.nombre).limit(200).all()
            self._productos_cache = productos
        finally:
            db.close()
        
        origen_dropdown = ft.Dropdown(
            label="Origen",
            options=[ft.dropdown.Option(a, a.title()) for a in opciones_almacen],
            value="principal",
            border_radius=10,
            expand=True,
        )
        
        destino_dropdown = ft.Dropdown(
            label="Destino",
            options=[ft.dropdown.Option(a, a.title()) for a in opciones_almacen],
            value="restaurante",
            border_radius=10,
            expand=True,
        )
        
        observaciones_input = ft.TextField(
            label="Observaciones",
            hint_text="Notas...",
            border_radius=10,
            multiline=True,
            min_lines=2,
        )
        
        productos_container = ft.Column([], spacing=5)
        self._productos_container = productos_container
        
        busqueda_input = ft.TextField(
            hint_text="Buscar producto...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=12,
            on_change=lambda e: self._filtrar_productos_busqueda(e.control.value, self._productos_cache, resultados_container),
        )
        
        resultados_container = ft.Column([], spacing=5)
        self._resultados_container = resultados_container
        
        def agregar_producto_rapido(producto, cantidad, peso=0):
            for fila in productos_container.controls:
                prod_label = fila.controls[0]
                if hasattr(prod_label, 'producto_id') and prod_label.producto_id == producto.id:
                    cant_input = fila.controls[1]
                    try:
                        cant_input.value = str(float(cant_input.value or "0") + cantidad)
                        cant_input.update()
                    except:
                        pass
                    return
            
            es_pesable = getattr(producto, 'es_pesable', False)
            
            cant_input = ft.TextField(
                value=str(cantidad),
                keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10,
                width=80,
            )
            
            peso_input = ft.TextField(
                value=str(peso) if es_pesable else "0",
                keyboard_type=ft.KeyboardType.NUMBER,
                border_radius=10,
                width=80,
                visible=es_pesable,
            )
            
            prod_label = ft.Text(
                producto.nombre,
                size=14,
                weight="bold",
                color=colors['text_primary'],
            )
            prod_label.producto_id = producto.id
            
            unit_text = ft.Text(
                producto.unidad_medida or "uds",
                size=12,
                color=colors['text_secondary'],
            )
            
            delete_btn = ft.IconButton(
                ft.Icons.DELETE_ROUNDED, 
                icon_color=colors['error'], 
                on_click=lambda _, pl=prod_label: self._eliminar_producto_row(pl, productos_container)
            )
            
            if es_pesable:
                fila = ft.Row([
                    prod_label,
                    cant_input,
                    unit_text,
                    peso_input,
                    ft.Text("kg", size=12, color=colors['text_secondary']),
                    delete_btn,
                ], spacing=5)
            else:
                fila = ft.Row([
                    prod_label,
                    cant_input,
                    unit_text,
                    delete_btn,
                ], spacing=5)
            
            productos_container.controls.append(fila)
            productos_container.update()
        
        self._agregar_producto_req = agregar_producto_rapido
        
        agregar_btn = ft.ElevatedButton(
            "Agregar",
            icon=ft.Icons.ADD,
            on_click=lambda _: self._show_agregar_producto_dialog(),
        )
        
        def on_confirmar(e):
            if not productos_container.controls:
                snack = ft.SnackBar(content=ft.Text("Agregue al menos un producto"), bgcolor=colors['warning'])
                self.page.overlay.append(snack)
                snack.open = True
                self.page.update()
                return
            
            db = next(get_db_adaptive())
            try:
                detalles = []
                origen = origen_dropdown.value or "principal"
                destino = destino_dropdown.value or "restaurante"
                
                for fila in productos_container.controls:
                    prod_label = fila.controls[0]
                    cant_input = fila.controls[1]
                    unidad_text = fila.controls[2]
                    
                    producto_id = getattr(prod_label, 'producto_id', None)
                    if producto_id and cant_input.value:
                        try:
                            cantidad = float(cant_input.value.replace(",", ""))
                            peso = 0
                            if len(fila.controls) > 3:
                                peso = float(fila.controls[3].value or "0")
                            
                            producto = db.query(Producto).filter(Producto.id == producto_id).first()
                            
                            
                            detalles.append({
                                "producto_id": producto_id,
                                "ingrediente": producto.nombre if producto else "Desconocido",
                                "cantidad": cantidad,
                                "peso": peso,
                                "unidad": unidad_text.value if hasattr(unidad_text, 'value') else str(unidad_text),
                            })
                        except ValueError:
                            pass
                
                req = Requisicion(
                    numero=f"REQ-{datetime.now().strftime('%Y%m%d%H%M%S')}",
                    numero_secuencial=0,
                    origen=origen,
                    destino=destino,
                    estado="completada",
                    observaciones=observaciones_input.value or "",
                    creada_por=(self.page.session.get("user_id") or "Admin") if self.page else "Admin",
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
                    
                    exist_orig = db.query(Existencia).filter(
                        Existencia.producto_id == d["producto_id"],
                        Existencia.almacen == origen
                    ).first()
                    if exist_orig:
                        exist_orig.cantidad = max(0, (exist_orig.cantidad or 0) - d["cantidad"])
                    
                    exist_dest = db.query(Existencia).filter(
                        Existencia.producto_id == d["producto_id"],
                        Existencia.almacen == destino
                    ).first()
                    if exist_dest:
                        exist_dest.cantidad = (exist_dest.cantidad or 0) + d["cantidad"]
                    else:
                        nueva_exist = Existencia(
                            producto_id=d["producto_id"],
                            almacen=destino,
                            cantidad=d["cantidad"]
                        )
                        db.add(nueva_exist)
                
                db.commit()
                self.active_dialog.open = False
                self.page.update()
                self._load_requisiciones()
                
                snack = ft.SnackBar(content=ft.Text(f"✓ {origen} → {destino}"), bgcolor=colors['success'])
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
            is_mobile = self.page.width < 700 if self.page else False
        
        almacenes_row = ft.Container(
            content=ft.Row([
                ft.Column([ft.Text("De", size=11, color=colors['text_secondary']), origen_dropdown], expand=True),
                ft.Icon(ft.Icons.ARROW_FORWARD, color=colors['text_secondary'], size=20),
                ft.Column([ft.Text("A", size=11, color=colors['text_secondary']), destino_dropdown], expand=True),
            ], spacing=10),
            padding=10,
            bgcolor=colors['card'],
            border_radius=10,
        )
        
        panel_productos = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Text("Productos", weight="bold", size=14, color=colors['text_primary']),
                    ft.Container(expand=True),
                    agregar_btn,
                ]),
                ft.Row([
                    ft.Container(content=busqueda_input, expand=True),
                ], spacing=5),
                ft.Container(
                    content=productos_container,
                    bgcolor=colors['bg'],
                    border_radius=10,
                    height=200,
                ),
            ], spacing=5),
            padding=10,
            bgcolor=colors['card'],
            border_radius=10,
        )
        
        if is_mobile:
            contenido = ft.Column([
                almacenes_row,
                panel_productos,
                observaciones_input,
            ], spacing=10, tight=True, scroll=ft.ScrollMode.AUTO)
        else:
            contenido = ft.Column([
                almacenes_row,
                panel_productos,
                observaciones_input,
            ], spacing=10, tight=True, scroll=ft.ScrollMode.AUTO)
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Text("Nueva Requisición", weight="bold"),
            content=ft.Container(
                content=contenido,
                width=450 if not is_mobile else None,
            ),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Crear", on_click=on_confirmar, bgcolor=colors['success'], color="white"),
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
        if not self.page:
            return
        
        colors = _colors(self.page)
        if req.estado == "completada":
            snack = ft.SnackBar(content=ft.Text("No se puede editar una requisición completada"), bgcolor=colors['warning'])
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            return
        
        self._show_crear_vista(requisicion=req)

    def _show_agregar_producto_dialog(self, productos_container):
        colors = _colors(self.page)
        db = next(get_db_adaptive())
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
        colors = _colors(self.page)
        
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
        if not self.page:
            return
        
        colors = _colors(self.page)
        db = next(get_db_adaptive())
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

    def _show_crear_vista(self, requisicion=None):
        """Muestra la vista de crear/editar requisición"""
        colors = _colors(self.page)
        is_mobile = self.page.width < 700 if self.page else False
        self._vista_actual = "crear"
        self._requisicion_editando = requisicion
        
        if requisicion:
            self.lista_productos_req = [
                {'producto_id': d.producto_id, 'nombre': d.ingrediente, 'cantidad': d.cantidad, 'unidad': d.unidad}
                for d in requisicion.detalles
            ]
        else:
            self.lista_productos_req = []
        
        db = next(get_db_adaptive())
        almacenes = []
        try:
            almacenes_result = db.query(Existencia.almacen).distinct().all()
            almacenes = [a[0] for a in almacenes_result]
            if "principal" not in almacenes:
                almacenes.append("principal")
            if "restaurante" not in almacenes:
                almacenes.append("restaurante")
        finally:
            db.close()
        
        origen_val = requisicion.origen if requisicion else "principal"
        destino_val = requisicion.destino if requisicion else "restaurante"
        
        origen_dropdown = ft.Dropdown(
            label="Desde",
            options=[ft.dropdown.Option(a, a.title()) for a in almacenes],
            value=origen_val,
            border_radius=10,
            expand=True,
        )
        
        self._origen_dropdown = origen_dropdown
        
        destino_dropdown = ft.Dropdown(
            label="Hacia",
            options=[ft.dropdown.Option(a, a.title()) for a in almacenes],
            value=destino_val,
            border_radius=10,
            expand=True,
        )
        
        almacenes_card = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Icon(ft.Icons.LOCATION_ON_OUTLINED, color=colors['accent'], size=20),
                    ft.Text("Ruta de Traslado", weight="bold", size=14, color=colors['text_primary']),
                ], spacing=10),
                ft.Divider(height=5),
                ft.Row([
                    ft.Column([ft.Text("Desde", size=11, color=colors['text_secondary']), origen_dropdown], expand=True),
                    ft.Icon(ft.Icons.ARROW_FORWARD, color=colors['text_secondary']),
                    ft.Column([ft.Text("Hacia", size=11, color=colors['text_secondary']), destino_dropdown], expand=True),
                ], spacing=10),
            ], spacing=5),
            padding=12,
            bgcolor=colors['card'],
            border_radius=12,
        )
        
        observaciones_input = ft.TextField(
            label="Observaciones",
            hint_text="Notas...",
            border_radius=10,
            multiline=True,
            min_lines=1,
            value=requisicion.observaciones if requisicion else "",
        )
        
        buscador = ft.TextField(
            hint_text="Buscar producto...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=12,
            on_change=lambda e: self._buscar_productos_buscador(e.control.value, resultados_container),
        )
        
        resultados_container = ft.ListView(
            expand=True,
            spacing=5,
            padding=5,
        )
        
        productos_lista = ft.ListView(
            expand=True,
            spacing=8,
            padding=10,
        )
        self._productos_lista_req = productos_lista
        
        def abrir_buscador(e):
            self._abrir_buscador_productos()
        
        boton_agregar = ft.ElevatedButton(
            icon=ft.Icons.ADD,
            text="Agregar Producto",
            on_click=abrir_buscador,
            bgcolor=colors['accent'],
            color="white",
        )
        
        titulo = f"Editar Requisición" if requisicion else "Nueva Requisición"
        btn_texto = "Actualizar" if requisicion else "Crear"
        btn_color = colors['accent'] if requisicion else colors['success']
        
        header = ft.Container(
            content=ft.Row([
                ft.IconButton(
                    ft.Icons.ARROW_BACK,
                    on_click=lambda _: self._volver_lista(),
                ),
                ft.Text(titulo, size=18, weight="bold", color=colors['text_primary']),
                ft.Container(expand=True),
                ft.ElevatedButton(
                    btn_texto,
                    on_click=lambda _: self._crear_requisicion_vista(origen_dropdown, destino_dropdown, observaciones_input),
                    bgcolor=btn_color,
                    color="white",
                ),
            ], spacing=10),
            padding=ft.padding.symmetric(horizontal=10, vertical=8),
            bgcolor=colors['surface'],
        )
        
        panel_productos = ft.Column([
            ft.Row([
                ft.Text(f"Productos ({len(self.lista_productos_req)})", weight="bold", size=14, color=colors['text_primary']),
                ft.Container(expand=True),
                boton_agregar,
            ], spacing=10),
            ft.Container(
                content=productos_lista,
                bgcolor=colors['bg'],
                border_radius=12,
                expand=True,
                padding=5,
            ),
        ], spacing=5)
        
        if is_mobile:
            contenido = ft.Column([
                header,
                almacenes_card,
                ft.Container(height=5),
                ft.Container(content=panel_productos, padding=10, expand=True),
            ], spacing=0, scroll=ft.ScrollMode.AUTO)
        else:
            row_busqueda = ft.Container(
                content=ft.Column([
                    ft.Text("Buscar productos", weight="bold", size=14, color=colors['text_primary']),
                    buscador,
                    ft.Container(
                        content=resultados_container,
                        bgcolor=colors['card'],
                        border_radius=10,
                        height=250,
                    ),
                ], spacing=5),
                width=320,
                padding=10,
            )
            contenido = ft.Column([
                header,
                almacenes_card,
                ft.Container(height=5),
                ft.Row([
                    row_busqueda,
                    ft.Container(content=panel_productos, expand=True, padding=10),
                ], spacing=10),
            ], spacing=0, scroll=ft.ScrollMode.AUTO)
        
        self._vista_crear = ft.Container(
            content=contenido,
            bgcolor=colors['bg'],
            padding=0,
        )
        
        self.content = self._vista_crear
        self.update()

    def _abrir_buscador_productos(self):
        """Abre el buscador de productos como BottomSheet"""
        colors = _colors(self.page)
        
        busqueda = ft.TextField(
            hint_text="Buscar producto...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=12,
            autofocus=True,
        )
        
        resultados = ft.ListView(
            expand=True,
            spacing=5,
            padding=5,
        )
        
        self._resultados_buscador = resultados
        
        self._bs_buscador = None
        
        def on_change(e):
            self._buscar_productos_buscador(e.control.value, resultados)
        
        busqueda.on_change = on_change
        
        def close(e):
            bs.open = False
            self.page.update()
        
        def agregar_y_cerrar(producto):
            self._agregar_producto_req(producto)
            bs.open = False
            self.page.update()
        
        bs = ft.BottomSheet(
            content=ft.Container(
                content=ft.Column([
                    ft.Row([
                        ft.Text("Buscar Producto", size=18, weight="bold"),
                        ft.IconButton(ft.Icons.CLOSE, on_click=close),
                    ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                    busqueda,
                    ft.Container(
                        content=resultados,
                        height=400,
                    ),
                ], spacing=10),
                padding=20,
            ),
            is_scroll_controlled=True,
            bgcolor=colors['surface'],
        )
        
        self.page.overlay.append(bs)
        self._bs_buscador = bs
        bs.open = True
        self.page.update()
        
        self._buscar_productos_buscador("", resultados)
        
        self._buscar_productos_buscador("", resultados)

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
            es_pesable = getattr(p, 'es_pesable', False)
            badge = ft.Container(
                content=ft.Text("PESABLE", size=9, color="white", weight="bold"),
                bgcolor=colors['warning'],
                padding=ft.padding.symmetric(horizontal=4, vertical=1),
                border_radius=3,
            ) if es_pesable else ft.Container()
            
            container.controls.append(
                ft.Container(
                    content=ft.Row([
                        ft.Column([
                            ft.Text(p.nombre, weight="bold", size=14, color=colors['text_primary']),
                            ft.Row([
                                ft.Text(f"{p.unidad_medida or 'uds'}", size=11, color=colors['text_secondary']),
                                badge,
                            ], spacing=5),
                        ], expand=True),
                        ft.Container(
                            content=ft.Icon(ft.Icons.ADD_CIRCLE, color=colors['success'], size=28),
                            on_click=lambda _, prod=p: self._agregar_producto_req(prod),
                            padding=5,
                        ),
                    ], spacing=10),
                    padding=12,
                    bgcolor=colors['card'],
                    border_radius=10,
                    ink=True,
                    on_click=lambda _, prod=p: self._agregar_producto_req(prod),
                )
            )
        
        if not resultados and texto:
            container.controls.append(
                ft.Text("Sin resultados", color=colors['text_secondary'], text_align="center")
            )
        
        container.update()
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
            es_pesable = getattr(p, 'es_pesable', False)
            badge = ft.Container(
                content=ft.Text("PESABLE", size=9, color="white", weight="bold"),
                bgcolor=colors['warning'],
                padding=ft.padding.symmetric(horizontal=4, vertical=1),
                border_radius=3,
            ) if es_pesable else ft.Container()
            
            container.controls.append(
                ft.Container(
                    content=ft.Row([
                        ft.Column([
                            ft.Text(p.nombre, weight="bold", size=13, color=colors['text_primary']),
                            ft.Row([
                                ft.Text(f"Unidad: {p.unidad_medida or 'uds'}", size=11, color=colors['text_secondary']),
                                badge,
                            ], spacing=5),
                        ], expand=True),
                        ft.IconButton(
                            ft.Icons.ADD_CIRCLE,
                            icon_color=colors['success'],
                            on_click=lambda _, prod=p: self._agregar_producto_req(prod),
                        ),
                    ], spacing=10),
                    padding=10,
                    bgcolor=colors['card'],
                    border_radius=8,
                )
            )
        
        if not resultados and texto:
            container.controls.append(ft.Text("Sin resultados", color=colors['text_secondary']))
        
        container.update()

    def _agregar_producto_req(self, producto):
        """Agrega un producto con diálogo de cantidad"""
        colors = _colors(self.page)
        es_pesable = getattr(producto, 'es_pesable', False)
        
        almacen_origen = getattr(self, '_origen_dropdown', None)
        origen = almacen_origen.value if almacen_origen else "principal"
        
        db = next(get_db_adaptive())
        disponible = 0
        try:
            exist = db.query(Existencia).filter(
                Existencia.producto_id == producto.id,
                Existencia.almacen == origen
            ).first()
            disponible = exist.cantidad if exist else 0
        finally:
            db.close()
        
        stock_color = colors['success'] if disponible > 0 else colors['error']
        
        cant_input = ft.TextField(
            label="Cantidad",
            value="1",
            keyboard_type=ft.KeyboardType.NUMBER,
            border_radius=10,
            width=100,
            autofocus=True,
        )
        
        peso_input = ft.TextField(
            label="Peso (kg)",
            value="0",
            keyboard_type=ft.KeyboardType.NUMBER,
            border_radius=10,
            width=100,
            visible=es_pesable,
        )
        
        stock_info = ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.INVENTORY_2_ROUNDED, size=16, color=stock_color),
                ft.Text(f"Disponible: {disponible} {producto.unidad_medida or 'uds'}", size=12, color=stock_color, weight="bold"),
            ], spacing=5),
            bgcolor=colors['card'],
            padding=10,
            border_radius=8,
        )
        
        def on_agregar(e):
            try:
                cantidad = int(float(cant_input.value.replace(",", "")))
                if cantidad <= 0:
                    raise ValueError()
            except:
                cant_input.error_text = "Inválido"
                cant_input.update()
                return
            
            peso = 0.0
            if es_pesable:
                try:
                    peso = float(peso_input.value.replace(",", "."))
                except:
                    peso = 0.0
            
            existe = next((item for item in self.lista_productos_req if item['producto_id'] == producto.id), None)
            if existe:
                existe['cantidad'] += cantidad
                existe['peso'] = (existe.get('peso') or 0) + peso
            else:
                self.lista_productos_req.append({
                    'producto_id': producto.id,
                    'nombre': producto.nombre,
                    'cantidad': cantidad,
                    'peso': peso,
                    'unidad': producto.unidad_medida or 'uds',
                    'es_pesable': es_pesable,
                })
            
            dialog.open = False
            self._actualizar_lista_productos()
            self.page.update()
            
            if hasattr(self, '_bs_buscador') and self._bs_buscador:
                self._bs_buscador.open = False
            
            snack = ft.SnackBar(content=ft.Text(f"+ {producto.nombre}"), bgcolor=colors['success'])
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
        
        dialog = ft.AlertDialog(
            title=ft.Text(f"Agregar: {producto.nombre}"),
            content=ft.Column([
                stock_info,
                ft.Container(height=10),
                ft.Text(f"Unidad: {producto.unidad_medida or 'uds'}", size=12, color=colors['text_secondary']),
                ft.Container(height=5),
                ft.Row([cant_input, peso_input], spacing=10) if es_pesable else cant_input,
            ], tight=True),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: setattr(dialog, 'open', False) or self.page.update()),
                ft.ElevatedButton("Agregar", on_click=on_agregar, bgcolor=colors['accent'], color="white"),
            ],
        )
        
        self.page.overlay.append(dialog)
        dialog.open = True
        self.page.update()

    def _actualizar_lista_productos(self):
        colors = _colors(self.page)
        self._productos_lista_req.controls.clear()
        
        if not self.lista_productos_req:
            self._productos_lista_req.controls.append(
                ft.Text("Sin productos agregados", color=colors['text_secondary'], text_align="center")
            )
        else:
            for i, item in enumerate(self.lista_productos_req):
                es_pesable = item.get('es_pesable', False)
                peso = item.get('peso', 0) or 0
                
                peso_badge = ft.Container()
                if es_pesable and peso > 0:
                    peso_badge = ft.Container(
                        content=ft.Text(f"{peso:.2f} kg", size=11, color=colors['warning'], weight="bold"),
                        bgcolor=colors.get('orange_50', colors['bg']),
                        padding=ft.padding.symmetric(horizontal=6, vertical=2),
                        border_radius=5,
                    )
                
                self._productos_lista_req.controls.append(
                    ft.Container(
                        content=ft.Row([
                            ft.Column([
                                ft.Text(f"{i+1}. {item['nombre']}", size=13, weight="bold", color=colors['text_primary']),
                                ft.Row([
                                    ft.Text(f"{item['cantidad']} {item['unidad']}", size=11, color=colors['accent']),
                                    peso_badge,
                                ], spacing=5),
                            ], expand=True),
                            ft.IconButton(
                                ft.Icons.DELETE_OUTLINE,
                                icon_color=colors['error'],
                                icon_size=20,
                                on_click=lambda _, idx=i: self._eliminar_producto_req(idx),
                            ),
                        ], spacing=10),
                        padding=12,
                        bgcolor=colors['card'],
                        border_radius=10,
                    )
                )
        
        self._productos_lista_req.update()

    def _eliminar_producto_req(self, idx):
        if idx < len(self.lista_productos_req):
            self.lista_productos_req.pop(idx)
            self._actualizar_lista_productos()

    def _crear_requisicion_vista(self, origen_dropdown, destino_dropdown, observaciones):
        if not self.lista_productos_req:
            snack = ft.SnackBar(content=ft.Text("Agregue al menos un producto"), bgcolor=ft.Colors.ORANGE_700)
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            return
        
        origen = origen_dropdown.value or "principal"
        destino = destino_dropdown.value or "restaurante"
        
        db = next(get_db_adaptive())
        try:
            req_editando = getattr(self, '_requisicion_editando', None)
            
            if req_editando:
                req_editando.origen = origen
                req_editando.destino = destino
                req_editando.observaciones = observaciones.value or ""
                
                for d in req_editando.detalles:
                    db.delete(d)
                db.flush()
                
                for item in self.lista_productos_req:
                    detalle = RequisicionDetalle(
                        requisicion_id=req_editando.id,
                        producto_id=item['producto_id'],
                        ingrediente=item['nombre'],
                        cantidad=item['cantidad'],
                        unidad=item['unidad'],
                    )
                    db.add(detalle)
                
                db.commit()
                snack = ft.SnackBar(content=ft.Text(f"✓ Requisición actualizada"), bgcolor=ft.Colors.GREEN_700)
            else:
                req = Requisicion(
                    numero=f"REQ-{datetime.now().strftime('%Y%m%d%H%M%S')}",
                    numero_secuencial=0,
                    origen=origen,
                    destino=destino,
                    estado="pendiente",
                    observaciones=observaciones.value or "",
                    created_by=(self.page.session.get("user_id") or "Admin") if self.page else "Admin",
                )
                db.add(req)
                db.flush()
                
                for item in self.lista_productos_req:
                    detalle = RequisicionDetalle(
                        requisicion_id=req.id,
                        producto_id=item['producto_id'],
                        ingrediente=item['nombre'],
                        cantidad=item['cantidad'],
                        unidad=item['unidad'],
                    )
                    db.add(detalle)
                
                db.commit()
                snack = ft.SnackBar(content=ft.Text(f"✓ Requisición creada: {origen} → {destino}"), bgcolor=ft.Colors.GREEN_700)
            
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            
            self.lista_productos_req = []
            self._requisicion_editando = None
            self._volver_lista()
            
        except Exception as ex:
            db.rollback()
            logger.error(f"Error guardando requisición: {ex}")
            snack = ft.SnackBar(content=ft.Text(f"Error: {ex}"), bgcolor=ft.Colors.RED_700)
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
        finally:
            db.close()

    def _volver_lista(self):
        """Regresa a la lista de requisiciones"""
        self._vista_actual = "lista"
        self.lista_productos_req = []
        self._build_ui()
        self.update()