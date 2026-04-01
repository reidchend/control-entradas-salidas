import flet as ft
import asyncio
from datetime import datetime
from usr.database.base import get_db
from usr.models import Categoria, Producto, Movimiento, Existencia
from usr.logger import get_logger
from sqlalchemy import func
import traceback

logger = get_logger(__name__)

class InventarioView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True 
        self.padding = ft.padding.only(left=10, right=10, bottom=16, top=8)
        self.bgcolor = ft.Colors.GREY_50

        # Componentes UI inicializados en None
        self.search_field = None
        self.productos_list = None
        self.active_dialog = None
        
        # Grid de categorías: 3 columnas y Scroll automático
        self.categorias_grid = ft.GridView(
            expand=True,
            runs_count=3,           
            max_extent=120,         
            child_aspect_ratio=0.8, 
            spacing=10,
            run_spacing=10,
        )

        self.main_content_area = ft.Container(
            content=self.categorias_grid,
            expand=True, 
        )

        self._vista_requisicion_activa = False
        self.panel_requisicion = None
        self.lista_requisicion = []
        self._productos_req = []

        self.categoria_seleccionada = None
        self.producto_seleccionado = None
        self._is_initialized = False
        self._categorias_cache = None

        self._build_ui()

    def did_mount(self):
        """Se ejecuta cuando el control se añade a la página."""
        if not self._is_initialized:
            # Usamos run_task para que la carga de datos no bloquee el renderizado inicial
            if self.page:
                self.page.run_task(self._load_categorias)
            self._is_initialized = True

    def _build_ui(self):
        try:
            self.header_container = ft.Container(
                content=ft.Row([
                    ft.Column([
                        ft.Text("Inventario", size=22, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_GREY_900),
                        ft.Text("Gestión de existencias", size=12, color=ft.Colors.BLUE_GREY_400),
                    ], expand=True, spacing=0),
                    ft.ElevatedButton(
                        content=ft.Row([
                            ft.Icon(ft.Icons.ASSIGNMENT, size=18),
                            ft.Text("Requisición"),
                        ], spacing=5),
                        on_click=lambda _: self._show_panel_requisicion(),
                        bgcolor=ft.Colors.ORANGE_600,
                        color="white",
                    ),
                    ft.IconButton(
                        icon=ft.Icons.REFRESH_ROUNDED,
                        on_click=lambda _: self.page.run_task(self._load_categorias, True),
                    )
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                margin=ft.margin.only(bottom=10)
            )

            self.search_field = ft.TextField(
                hint_text="Buscar...",
                prefix_icon=ft.Icons.SEARCH_ROUNDED,
                border_radius=12,
                bgcolor=ft.Colors.WHITE,
                height=45,
                text_size=14,
                on_change=self._on_search_change,
            )

            self.content = ft.Column([
                self.header_container,
                self.search_field,
                ft.Container(height=5),
                self.main_content_area, 
            ], spacing=0, expand=True) 
            
        except Exception as e:
            logger.error(f"Error UI: {e}")

    async def _load_categorias(self, force_refresh=False):
        db = None
        try:
            db = next(get_db())
            categorias = db.query(Categoria).all()
            self._categorias_cache = categorias
            
            if not categorias:
                self.categorias_grid.controls = [ft.Text("No hay categorías")]
            else:
                self.categorias_grid.controls = [self._create_categoria_card(c) for c in categorias]
            
            # Solo actualizamos si el componente está montado en la página
            if self.page:
                self.update()
        except Exception as e:
            logger.error(f"Error carga: {e}")
        finally:
            if db: db.close()

    async def _handle_category_click(self, container, categoria):
        """Maneja la animación y el cambio de vista."""
        try:
            container.scale = 0.95
            container.bgcolor = ft.Colors.BLUE_GREY_200
            container.update()
            await asyncio.sleep(0.1)
            container.scale = 1.0
            container.bgcolor = ft.Colors.WHITE
            container.update()
            await asyncio.sleep(0.15)
            self._show_productos(categoria)
        except Exception as e:
            logger.error(f"Error en clic categoría: {e}")

    def _create_categoria_card(self, categoria):
        cat_color = categoria.color if categoria.color else "#2563eb"
        
        card = ft.Container(
            bgcolor="#f0f4f8",
            border_radius=20,
            padding=20,
            animate_scale=200,
            scale=1.0,
            shadow=ft.BoxShadow(
                color=ft.Colors.with_opacity(0.3, cat_color),
                blur_radius=10,
                offset=ft.Offset(0, 4),
                spread_radius=0,
            ),
            border=ft.border.all(1, ft.Colors.with_opacity(0.2, cat_color)),
            content=ft.Column([
                ft.Container(
                    content=ft.Icon(ft.Icons.CATEGORY_ROUNDED, size=36, color="white"),
                    bgcolor=cat_color,
                    width=64,
                    height=64,
                    border_radius=32,
                    alignment=ft.alignment.center,
                ),
                ft.Container(height=10),
                ft.Text(
                    str(categoria.nombre).upper(), 
                    weight="bold", 
                    size=12, 
                    text_align="center", 
                    color=cat_color,
                    max_lines=2,
                    overflow=ft.TextOverflow.ELLIPSIS
                ),
            ], alignment="center", horizontal_alignment="center", spacing=0)
        )

        # Capturamos el evento 'e' para que no se confunda con 'container'
        card.on_click = lambda e: self.page.run_task(self._handle_category_click, card, categoria)
        return card

    def _show_productos(self, categoria):
        self.categoria_seleccionada = categoria
        header_nav = ft.Row([
            ft.IconButton(ft.Icons.ARROW_BACK_ROUNDED, on_click=lambda _: self._reset_view()),
            ft.Text(categoria.nombre, size=18, weight="bold", color=categoria.color),
        ])
        
        self.productos_list = ft.ListView(expand=True, spacing=10, padding=ft.padding.only(top=10))
        
        nueva_vista = ft.Column([header_nav, self.productos_list], expand=True)
        self.main_content_area.content = nueva_vista
        self._load_productos()
        if self.page: self.update()

    def _reset_view(self):
        self.categoria_seleccionada = None
        self.search_field.value = ""
        self.main_content_area.content = self.categorias_grid
        # Refrescamos el grid para asegurar el estado limpio
        if self._categorias_cache:
            self.categorias_grid.controls = [self._create_categoria_card(c) for c in self._categorias_cache]
        if self.page: self.update()

    def _load_productos(self, search_term=""):
        if not self.categoria_seleccionada: return
        db = None
        try:
            db = next(get_db())
            
            productos = db.query(Producto).filter(Producto.categoria_id == self.categoria_seleccionada.id).all()
            producto_ids = [p.id for p in productos]
            
            existencias_map = {}
            if producto_ids:
                existencias = db.query(Existencia.producto_id, Existencia.almacen, Existencia.cantidad).filter(
                    Existencia.producto_id.in_(producto_ids)
                ).all()
                for e in existencias:
                    if e.producto_id not in existencias_map:
                        existencias_map[e.producto_id] = {}
                    existencias_map[e.producto_id][e.almacen] = e.cantidad
            
            if search_term:
                productos = [p for p in productos if search_term.lower() in p.nombre.lower()]
            
            items = [self._create_producto_item(p, existencias_map.get(p.id, {})) for p in productos if p]
            self.productos_list.controls = items if items else [ft.Text("No hay productos")]
            if self.page: self.update()
        except Exception as e:
            logger.error(f"Error carga productos: {e}")
        finally:
            if db: db.close()

    def _create_producto_item(self, producto, stock_por_almacen=None):
        if stock_por_almacen is None:
            stock_por_almacen = {}
        stock = sum(stock_por_almacen.values()) or 0
        stock_min = producto.stock_minimo or 0
        stock_color = ft.Colors.RED_600 if stock < stock_min else ft.Colors.PRIMARY
        
        es_pesable = getattr(producto, 'es_pesable', False)
        badge_pesable = ft.Container(
            content=ft.Text("PESABLE", size=9, color=ft.Colors.WHITE, weight="bold"),
            bgcolor=ft.Colors.ORANGE_700,
            padding=ft.padding.symmetric(horizontal=4, vertical=1),
            border_radius=3
        ) if es_pesable else ft.Container()

        return ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Row([ft.Text(str(producto.nombre), weight="bold", size=14), badge_pesable], spacing=5),
                    ft.Row([
                        ft.Container(
                            content=ft.Text(f"Stock: {stock}", size=10, weight="bold", color=ft.Colors.WHITE),
                            bgcolor=stock_color, padding=ft.padding.symmetric(horizontal=6, vertical=2), border_radius=5
                        ),
                        ft.Text(f"Mín: {stock_min}", size=10, color=ft.Colors.GREY_500),
                    ], spacing=10)
                ], expand=True),
                ft.IconButton(ft.Icons.ADD_CIRCLE_OUTLINE_ROUNDED, icon_color="green", icon_size=24,
                             on_click=lambda _, p=producto: self._show_cantidad_dialog(p, "entrada")),
                ft.IconButton(ft.Icons.REMOVE_CIRCLE_OUTLINE_ROUNDED, icon_color="red", icon_size=24,
                             on_click=lambda _, p=producto: self._show_cantidad_dialog(p, "salida")),
            ], spacing=5),
            padding=10, bgcolor=ft.Colors.WHITE, border_radius=10, border=ft.border.all(1, "#eeeeee")
        )

    def _get_almacenes(self):
        db = next(get_db())
        try:
            almacenes = db.query(Existencia.almacen).distinct().all()
            opciones = [a[0] for a in almacenes]
            if "principal" not in opciones:
                opciones.insert(0, "principal")
            return opciones
        finally:
            db.close()

    def _show_cantidad_dialog(self, producto, tipo):
        self.producto_seleccionado = producto
        es_pesable = getattr(producto, 'es_pesable', False)
        
        almacen_default = producto.almacen_predeterminado or "principal"
        
        db = next(get_db())
        try:
            existencias = db.query(Existencia).filter(Existencia.producto_id == producto.id).all()
            stock_por_almacen = {e.almacen: e.cantidad for e in existencias}
            todos_almacenes = db.query(Existencia.almacen).distinct().all()
            almacenes_disponibles = [a[0] for a in todos_almacenes]
            if "principal" not in almacenes_disponibles:
                almacenes_disponibles.append("principal")
        finally:
            db.close()
        
        cant_input = ft.TextField(label="Unidades/Bultos", value="1", keyboard_type=ft.KeyboardType.NUMBER, autofocus=True, suffix_text="uds")
        peso_input = ft.TextField(label="Peso Total (Kg)", hint_text="0.00", keyboard_type=ft.KeyboardType.NUMBER, visible=es_pesable, suffix_text="kg")
        
        almacen_options = [ft.dropdown.Option(a, a.capitalize()) for a in almacenes_disponibles]
        almacen_dropdown = ft.Dropdown(
            label="Almacén",
            value=almacen_default,
            options=almacen_options
        )
        
        stock_texts = [ft.Text(f"{k.capitalize()}: {v:.0f}", size=11) for k, v in stock_por_almacen.items()]
        if not stock_texts:
            stock_texts = [ft.Text("Sin stock", size=11)]
        
        stock_info = ft.Container(
            content=ft.Column([
                ft.Text("Stock por almacén:", size=12, weight="bold"),
            ] + stock_texts, spacing=2),
            bgcolor=ft.Colors.BLUE_50,
            padding=10,
            border_radius=8,
            margin=ft.margin.only(bottom=10)
        )

        def al_confirmar(e):
            try:
                valor = cant_input.value.replace(",", "").replace(" ", "")
                cantidad = int(float(valor))
                if cantidad <= 0: raise ValueError()
            except (ValueError, AttributeError):
                cant_input.error_text = "Número entero mayor a 0"; cant_input.update(); return

            peso_valor = 0.0
            if es_pesable:
                try:
                    peso_valor = float(peso_input.value.replace(',', '.'))
                    if peso_valor <= 0: raise ValueError()
                except ValueError:
                    peso_input.error_text = "Ingrese un peso válido"; peso_input.update(); return

            almacen = almacen_dropdown.value or "principal"
            self._close_dialog()
            self._registrar_movimiento(tipo, cantidad, peso_total=peso_valor, almacen=almacen)

        self.active_dialog = ft.AlertDialog(
            title=ft.Text(f"Registrar {tipo.capitalize()}"),
            content=ft.Column([
                ft.Text(f"Producto: {producto.nombre}", weight="bold"),
                stock_info,
                almacen_dropdown,
                cant_input, 
                peso_input
            ], tight=True, spacing=10),
            actions=[ft.TextButton("Cancelar", on_click=self._close_dialog), ft.ElevatedButton("Confirmar", on_click=al_confirmar)]
        )
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        if self.page: self.page.update()

    def _registrar_movimiento(self, tipo, cantidad, peso_total=0.0, almacen=None):
        db = None
        try:
            db = next(get_db())
            prod = db.query(Producto).filter(Producto.id == self.producto_seleccionado.id).first()
            user_id = self.page.session.get("user_id") or 1
            
            almacen_seleccionado = almacen or prod.almacen_predeterminado or "principal"
            
            existencia = db.query(Existencia).filter(
                Existencia.producto_id == prod.id,
                Existencia.almacen == almacen_seleccionado
            ).first()
            
            cant_anterior = existencia.cantidad if existencia else 0
            
            if tipo == "entrada":
                cant_nueva = cant_anterior + cantidad
            else:
                if cant_anterior < cantidad:
                    self._show_error("Stock insuficiente"); return
                cant_nueva = cant_anterior - cantidad

            if existencia:
                existencia.cantidad = cant_nueva
            else:
                existencia = Existencia(
                    producto_id=prod.id,
                    almacen=almacen_seleccionado,
                    cantidad=cant_nueva,
                    unidad=prod.unidad_medida or "unidad"
                )
                db.add(existencia)

            stock_total = db.query(func.coalesce(func.sum(Existencia.cantidad), 0)).filter(
                Existencia.producto_id == prod.id
            ).scalar() or 0

            nuevo_mov = Movimiento(
                producto_id=prod.id, tipo=tipo, cantidad=cantidad,
                cantidad_anterior=cant_anterior, cantidad_nueva=cant_nueva,
                registrado_por=user_id, fecha_movimiento=datetime.now(), 
                peso_total=peso_total, almacen=almacen_seleccionado
            )
            prod.stock_actual = stock_total
            db.add(nuevo_mov)
            db.commit()
            
            self._show_message(f"✓ {tipo.capitalize()} registrada en {almacen_seleccionado}")
            self._load_productos(search_term=self.search_field.value)
        except Exception as e:
            if db: db.rollback()
            self._show_error(f"Error: {e}")
        finally:
            if db: db.close()

    def _on_search_change(self, e):
        term = e.control.value.lower()
        if self.categoria_seleccionada:
            self._load_productos(term)
        elif self._categorias_cache:
            filtered = [c for c in self._categorias_cache if term in c.nombre.lower()]
            self.categorias_grid.controls = [self._create_categoria_card(c) for c in filtered]
            self.categorias_grid.update()

    def _close_dialog(self, e=None):
        if self.active_dialog:
            self.active_dialog.open = False
            if self.page: self.page.update()

    def _show_message(self, texto):
        snack = ft.SnackBar(content=ft.Text(texto), bgcolor=ft.Colors.GREEN_700)
        self.page.overlay.append(snack)
        snack.open = True
        if self.page: self.page.update()

    def _show_error(self, texto):
        snack = ft.SnackBar(content=ft.Text(texto), bgcolor=ft.Colors.RED_700)
        self.page.overlay.append(snack)
        snack.open = True
        if self.page: self.page.update()

    def _show_panel_requisicion(self, requisicion_editar=None):
        self.lista_requisicion = []
        self._vista_requisicion_activa = True
        self._productos_req = []
        self._requisicion_editar_id = requisicion_editar.id if requisicion_editar else None
        
        db = next(get_db())
        try:
            productos = db.query(Producto).filter(Producto.activo == True).order_by(Producto.nombre).limit(200).all()
            self._productos_req = productos
            almacenes = db.query(Existencia.almacen).distinct().all()
            opciones_almacen = [a[0] for a in almacenes]
            if "principal" not in opciones_almacen:
                opciones_almacen.append("principal")
            
            from usr.models import Requisicion
            ultimo_numero = db.query(func.coalesce(func.max(Requisicion.numero_secuencial), 0)).scalar() or 0
            siguiente_numero = ultimo_numero + 1
            
            if requisicion_editar:
                from usr.models import RequisicionDetalle
                detalles = db.query(RequisicionDetalle).filter(
                    RequisicionDetalle.requisicion_id == requisicion_editar.id
                ).all()
                self.lista_requisicion = [
                    {
                        "producto_id": d.producto_id,
                        "nombre": d.ingrediente,
                        "cantidad": d.cantidad,
                        "unidad": d.unidad,
                    }
                    for d in detalles
                ]
                numero_siguiente = requisicion_editar.numero_secuencial
            else:
                numero_siguiente = siguiente_numero
        finally:
            db.close()
        
        numero_input = ft.TextField(
            label="N° Requisición",
            value=f"REQ-{numero_siguiente:04d}",
            border_radius=10,
            width=150,
            read_only=True,
            bgcolor=ft.Colors.GREY_100,
        )
        
        origen_dropdown = ft.Dropdown(
            label="Origen",
            options=[ft.dropdown.Option(a, a.capitalize()) for a in opciones_almacen],
            value=requisicion_editar.origen if requisicion_editar else "principal",
            border_radius=10,
            width=150,
        )
        
        destino_dropdown = ft.Dropdown(
            label="Destino",
            options=[ft.dropdown.Option(a, a.capitalize()) for a in opciones_almacen],
            value=requisicion_editar.destino if requisicion_editar else "restaurante",
            border_radius=10,
            width=150,
        )
        
        busqueda_input = ft.TextField(
            hint_text="Buscar producto...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=10,
            expand=True,
        )
        
        cantidad_input = ft.TextField(
            label="Cant.",
            value="1",
            keyboard_type=ft.KeyboardType.NUMBER,
            border_radius=10,
            width=80,
        )
        
        resultados_list = ft.ListView(expand=True, spacing=5)
        
        tabla_pendientes = ft.ListView(expand=True, spacing=5)
        
        cantidad_label = ft.Text("0", size=16, weight="bold", color=ft.Colors.BLUE_700)
        
        def actualizar_tabla():
            cantidad_label.value = str(len(self.lista_requisicion))
            tabla_pendientes.controls.clear()
            if not self.lista_requisicion:
                tabla_pendientes.controls.append(
                    ft.Container(
                        content=ft.Text("Sin productos agregados", color=ft.Colors.GREY_400, text_align="center"),
                        padding=40,
                    )
                )
            else:
                for i, item in enumerate(self.lista_requisicion):
                    tabla_pendientes.controls.append(
                        ft.Container(
                            content=ft.Row([
                                ft.Text(f"{i+1}.", size=12, color=ft.Colors.GREY_500, width=30),
                                ft.Text(item["nombre"], size=13, expand=True),
                                ft.Text(f"{item['cantidad']:.2f} {item['unidad']}", size=12, color=ft.Colors.BLUE_700, weight="bold"),
                                ft.IconButton(
                                    ft.Icons.DELETE_OUTLINE, 
                                    icon_color=ft.Colors.RED_400,
                                    icon_size=18,
                                    on_click=lambda _, idx=i: self._eliminar_item_req(idx, tabla_pendientes),
                                ),
                            ], spacing=10),
                            padding=12,
                            bgcolor=ft.Colors.GREY_50,
                            border_radius=8,
                        )
                    )
            cantidad_label.update()
            tabla_pendientes.update()
        
        def agregar_producto(e):
            texto = busqueda_input.value.lower()
            if not texto:
                return
            
            filtrados = [p for p in self._productos_req if texto in p.nombre.lower()]
            if filtrados:
                producto = filtrados[0]
                try:
                    cantidad = float(cantidad_input.value.replace(",", ""))
                    if cantidad <= 0:
                        raise ValueError()
                except:
                    self._show_error("Cantidad inválida")
                    return
                
                for item in self.lista_requisicion:
                    if item["producto_id"] == producto.id:
                        item["cantidad"] += cantidad
                        actualizar_tabla()
                        return
                
                self.lista_requisicion.append({
                    "producto_id": producto.id,
                    "nombre": producto.nombre,
                    "cantidad": cantidad,
                    "unidad": producto.unidad_medida or "unidad",
                })
                cantidad_input.value = "1"
                actualizar_tabla()
        
        def limpiar_lista(e):
            self.lista_requisicion.clear()
            actualizar_tabla()
        
        def cerrar_vista(e):
            self._vista_requisicion_activa = False
            self.main_content_area.content = self.categorias_grid
            self.search_field.visible = True
            if self.categoria_seleccionada:
                self._show_productos(self.categoria_seleccionada)
            self.update()
        
        def guardar_requisicion(e):
            if not numero_input.value:
                self._show_error("Ingresa el número de requisición")
                return
            if not self.lista_requisicion:
                self._show_error("Agrega productos a la requisición")
                return
            
            db = next(get_db())
            try:
                from usr.models import Requisicion, RequisicionDetalle
                
                if self._requisicion_editar_id:
                    req = db.query(Requisicion).filter(Requisicion.id == self._requisicion_editar_id).first()
                    if not req:
                        self._show_error("Requisición no encontrada")
                        return
                    req.numero = numero_input.value
                    req.origen = origen_dropdown.value or "principal"
                    req.destino = destino_dropdown.value or "restaurante"
                    
                    db.query(RequisicionDetalle).filter(
                        RequisicionDetalle.requisicion_id == req.id
                    ).delete()
                    
                    for item in self.lista_requisicion:
                        detalle = RequisicionDetalle(
                            requisicion_id=req.id,
                            producto_id=item["producto_id"],
                            ingrediente=item["nombre"],
                            cantidad=item["cantidad"],
                            unidad=item["unidad"],
                        )
                        db.add(detalle)
                    
                    db.commit()
                    self._show_message(f"✓ Requisición #{req.numero} actualizada")
                else:
                    ultimo = db.query(func.coalesce(func.max(Requisicion.numero_secuencial), 0)).scalar() or 0
                    nuevo_numero_seq = ultimo + 1
                    
                    req = Requisicion(
                        numero=numero_input.value,
                        numero_secuencial=nuevo_numero_seq,
                        origen=origen_dropdown.value or "principal",
                        destino=destino_dropdown.value or "restaurante",
                        estado="pendiente",
                        creada_por=self.page.session.get("user_id") or "Admin",
                    )
                    db.add(req)
                    db.flush()
                    
                    for item in self.lista_requisicion:
                        detalle = RequisicionDetalle(
                            requisicion_id=req.id,
                            producto_id=item["producto_id"],
                            ingrediente=item["nombre"],
                            cantidad=item["cantidad"],
                            unidad=item["unidad"],
                        )
                        db.add(detalle)
                    
                    db.commit()
                    self._show_message(f"✓ Requisición #{req.numero} guardada")
                
                self.lista_requisicion.clear()
                self._requisicion_editar_id = None
                cerrar_vista(None)
                
            except Exception as ex:
                db.rollback()
                self._show_error(f"Error: {ex}")
            finally:
                db.close()
        
        titulo_texto = f"Editar Requisición #{requisicion_editar.numero}" if requisicion_editar else "Nueva Requisición"
        subtitulo_texto = "Modifica los productos y guarda los cambios" if requisicion_editar else "Agrega productos para crear una requisición"
        
        panel_content = ft.Column([
            ft.Container(
                content=ft.Row([
                    ft.IconButton(
                        ft.Icons.ARROW_BACK,
                        on_click=cerrar_vista,
                    ),
                    ft.Column([
                        ft.Text(titulo_texto, size=20, weight="bold"),
                        ft.Text(subtitulo_texto, size=12, color=ft.Colors.GREY_500),
                    ], spacing=0),
                    ft.Container(expand=True),
                ]),
                padding=15,
                bgcolor=ft.Colors.ORANGE_50,
            ),
            ft.Container(height=10),
            ft.Container(
                content=ft.Column([
                    ft.Text("CONFIGURACIÓN", size=11, weight="bold", color=ft.Colors.GREY_500),
                    ft.Container(height=8),
                    ft.ResponsiveRow([
                        ft.Column([numero_input], col={"xs": 12, "sm": 4}),
                        ft.Column([origen_dropdown], col={"xs": 12, "sm": 4}),
                        ft.Column([destino_dropdown], col={"xs": 12, "sm": 4}),
                    ]),
                ], spacing=0),
                padding=ft.padding.symmetric(horizontal=15),
            ),
            ft.Container(height=15),
            ft.Container(
                content=ft.Column([
                    ft.Text("AGREGAR PRODUCTOS", size=11, weight="bold", color=ft.Colors.GREY_500),
                    ft.Container(height=8),
                    ft.Row([
                        busqueda_input,
                        cantidad_input,
                        ft.ElevatedButton(
                            "Agregar",
                            icon=ft.Icons.ADD,
                            on_click=agregar_producto,
                            bgcolor=ft.Colors.GREEN_600,
                            color="white",
                        ),
                    ], spacing=10),
                ], spacing=0),
                padding=ft.padding.symmetric(horizontal=15),
            ),
            ft.Container(height=15),
            ft.Container(
                content=ft.Row([
                    ft.Text("PRODUCTOS EN REQUISICIÓN", size=11, weight="bold", color=ft.Colors.GREY_500),
                    ft.Container(expand=True),
                    ft.Container(
                        content=ft.Row([
                            ft.Text("Total: ", size=11),
                            cantidad_label,
                            ft.Text(" items", size=11),
                        ], spacing=2),
                        bgcolor=ft.Colors.BLUE_50,
                        padding=ft.padding.symmetric(horizontal=10, vertical=5),
                        border_radius=15,
                    ),
                ]),
                padding=ft.padding.symmetric(horizontal=15),
            ),
            ft.Container(
                content=tabla_pendientes,
                padding=ft.padding.symmetric(horizontal=15),
                expand=True,
            ),
            ft.Container(
                content=ft.Row([
                    ft.OutlinedButton("Limpiar", on_click=limpiar_lista),
                    ft.Container(expand=True),
                    ft.ElevatedButton(
                        "Guardar Requisición",
                        icon=ft.Icons.SAVE,
                        on_click=guardar_requisicion,
                        bgcolor=ft.Colors.ORANGE_600,
                        color="white",
                    ),
                ], spacing=10),
                padding=15,
            ),
        ], spacing=0, expand=True)
        
        self._actualizar_tabla_req = actualizar_tabla
        self._tabla_req_ref = tabla_pendientes
        self.search_field.visible = False
        self.main_content_area.content = panel_content
        self.update()
        actualizar_tabla()

    def _filtrar_productos_req(self, texto, container):
        container.controls.clear()
        if not texto or len(texto) < 2:
            for p in self._productos_req[:20]:
                container.controls.append(self._crear_item_producto_req(p, None, None, container))
        else:
            texto_lower = texto.lower()
            filtrados = [p for p in self._productos_req if texto_lower in p.nombre.lower()]
            for p in filtrados[:20]:
                container.controls.append(self._crear_item_producto_req(p, None, None, container))
        container.update()

    def _crear_item_producto_req(self, producto, cantidad_input, busqueda_input, container):
        stock_texto = ""
        db = next(get_db())
        try:
            total = db.query(func.coalesce(func.sum(Existencia.cantidad), 0)).filter(
                Existencia.producto_id == producto.id
            ).scalar() or 0
            stock_texto = f"Stock: {total:.0f}"
        finally:
            db.close()
        
        return ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Text(producto.nombre, size=13, weight="bold"),
                    ft.Text(f"{producto.unidad_medida or 'unidad'} | {stock_texto}", size=11, color=ft.Colors.GREY_500),
                ], expand=True),
            ]),
            padding=10,
            bgcolor=ft.Colors.GREY_50,
            border_radius=8,
            on_click=lambda _, p=producto: self._seleccionar_producto_req(p),
        )

    def _seleccionar_producto_req(self, producto):
        cantidad_input = ft.TextField(
            label="Cantidad",
            value="1",
            keyboard_type=ft.KeyboardType.NUMBER,
            border_radius=10,
            width=100,
        )
        
        def agregar():
            try:
                cantidad = float(cantidad_input.value.replace(",", ""))
                if cantidad <= 0:
                    raise ValueError()
            except:
                self._show_error("Cantidad inválida")
                return
            
            for item in self.lista_requisicion:
                if item["producto_id"] == producto.id:
                    item["cantidad"] += cantidad
                    self._actualizar_tabla_req()
                    return
            
            self.lista_requisicion.append({
                "producto_id": producto.id,
                "nombre": producto.nombre,
                "cantidad": cantidad,
                "unidad": producto.unidad_medida or "unidad",
            })
            self._actualizar_tabla_req()
        
        dialog = ft.AlertDialog(
            title=ft.Text(f"Agregar: {producto.nombre}"),
            content=ft.Column([
                ft.Text(f"Unidad: {producto.unidad_medida or 'unidad'}", size=12, color=ft.Colors.GREY_500),
                cantidad_input,
            ]),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Agregar", on_click=agregar, bgcolor=ft.Colors.GREEN_600, color="white"),
            ],
        )
        self.active_dialog = dialog
        self.page.overlay.append(dialog)
        dialog.open = True
        self.page.update()

    def _eliminar_item_req(self, idx, tabla):
        if idx < len(self.lista_requisicion):
            self.lista_requisicion.pop(idx)
            tabla.controls.clear()
            if not self.lista_requisicion:
                tabla.controls.append(
                    ft.Container(
                        content=ft.Text("Sin productos agregados", color=ft.Colors.GREY_400, text_align="center"),
                        padding=20,
                    )
                )
            else:
                for i, item in enumerate(self.lista_requisicion):
                    tabla.controls.append(
                        ft.Container(
                            content=ft.Row([
                                ft.Text(f"{i+1}.", size=12, color=ft.Colors.GREY_500, width=30),
                                ft.Text(item["nombre"], size=13, weight="bold", expand=True),
                                ft.Text(f"{item['cantidad']:.2f} {item['unidad']}", size=12, color=ft.Colors.BLUE_700),
                                ft.IconButton(
                                    ft.Icons.DELETE_OUTLINE, 
                                    icon_color=ft.Colors.RED_400,
                                    icon_size=18,
                                    on_click=lambda _, index=i: self._eliminar_item_req(index, tabla),
                                ),
                            ], spacing=10),
                            padding=10,
                            bgcolor=ft.Colors.GREY_50,
                            border_radius=8,
                        )
                    )
            tabla.update()