import flet as ft
import traceback
from usr.database.base import get_db, get_db_adaptive, check_connection
from usr.models import Categoria, Producto, Movimiento
from sqlalchemy.orm import joinedload
from sqlalchemy import text
from usr.theme import get_theme, get_colors
from usr.database.local_replica import LocalReplica
from datetime import datetime
from usr.notifications import show_success, show_error, show_warning


def _colors(page):
    return get_colors(page)


def _c(page, color_name):
    """Mapea colores de ft.Colors a tema dinámico"""
    colors = _colors(page)
    mapping = {
        'WHITE': colors['white'],
        'GREY_300': colors['text_hint'],
        'GREY_400': colors['text_secondary'],
        'GREY_500': colors['text_secondary'],
        'GREY_600': colors['text_secondary'],
        'GREY_50': colors['bg'],
        'BLUE_GREY_900': colors['text_primary'],
        'BLUE_GREY_800': colors['text_primary'],
        'BLUE_600': colors['accent'],
        'BLUE_700': colors['accent'],
        'GREEN_600': colors['success'],
        'GREEN_700': colors['success'],
        'RED_600': colors['error'],
        'RED_700': colors['error'],
        'ORANGE_600': colors['warning'],
        'ORANGE_700': colors['warning'],
    }
    return mapping.get(color_name, colors['text_primary'])


class ConfiguracionView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.padding = 0
        self.bgcolor = "#1A1A1A"
        
        self.selected_image_path = None
        self.active_dialog = None
        self.active_snackbar = None
        self.is_mobile = False
        
        self.lista_categorias = ft.Column(expand=True, spacing=12, scroll=ft.ScrollMode.AUTO)
        self.lista_productos = ft.Column(expand=True, spacing=12, scroll=ft.ScrollMode.AUTO)
        self.test_result_text = ft.Text("", size=14, weight=ft.FontWeight.BOLD)
        
        from usr.database import base
        is_online = base.is_online()
        
        self.offline_status_indicator = ft.Text(
            "🟢 ONLINE" if is_online else "📴 OFFLINE",
            size=14,
            color=ft.Colors.GREEN_400 if is_online else ft.Colors.RED_400,
            weight=ft.FontWeight.BOLD,
        )
        
        colors = _colors(None)  # Default for __init__

    def did_mount(self):
        self._build_ui()
        if self.page:
            self.is_mobile = self.page.width < 768
            self.page.on_resize = self._on_resize
            self._load_data()

    def on_theme_change(self):
        """Se llama cuando cambia el tema - solo actualizar colores, no reconstruir UI"""
        if not self.page:
            return
        colors = _colors(self.page)
        self.bgcolor = colors['bg']
        # NO llamar _build_ui() - solo actualizar colores existentes
        self.update()

    def _on_resize(self, e):
        self.is_mobile = self.page.width < 768
        self.update()

    def _build_ui(self):
        colors = _colors(self.page)
        header = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(
                        content=ft.Icon(ft.Icons.SETTINGS, size=32, color=colors['white']),
                        bgcolor=colors['accent'],
                        padding=12,
                        border_radius=12
                    ),
                    ft.Column([
                        ft.Text("Configuración", size=26, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                        ft.Text("Gestione categorías y catálogo de productos", size=13, color=colors['text_secondary']),
                    ], spacing=2, expand=True),
                ], alignment=ft.MainAxisAlignment.START),
            ], spacing=8),
            padding=ft.padding.only(left=20, right=20, top=20, bottom=15),
            bgcolor=colors['surface'],
            border_radius=ft.border_radius.only(bottom_left=20, bottom_right=20),
        )

        self.tabs = ft.Tabs(
            selected_index=0,
            animation_duration=300,
            scrollable=True,
            tabs=[
                ft.Tab(
                    text="Categorías", 
                    icon=ft.Icons.CATEGORY,
                    content=self._build_categorias_tab(),
                ),
                ft.Tab(
                    text="Productos", 
                    icon=ft.Icons.INVENTORY_2,
                    content=self._build_productos_tab(),
                ),
                ft.Tab(
                    text="Proveedores", 
                    icon=ft.Icons.LOCAL_SHIPPING,
                    content=self._build_proveedores_tab(),
                ),
                ft.Tab(
                    text="Sistema", 
                    icon=ft.Icons.DASHBOARD_CUSTOMIZE,
                    content=self._build_sistema_tab(),
                ),
            ],
            expand=True,
        )

        self.content = ft.Column([header, self.tabs], expand=True, spacing=0)

    def _build_categorias_tab(self):
        colors = _colors(self.page)
        fab_content = ft.Row([
            ft.Icon(ft.Icons.ADD, size=20),
            ft.Text("Nueva Categoría" if not self.is_mobile else "Nueva", weight=ft.FontWeight.BOLD),
        ], alignment=ft.MainAxisAlignment.CENTER, spacing=8)

        # Search field for categorias
        self.categoria_search = ft.TextField(
            hint_text="Buscar categorías...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=10,
            bgcolor=colors['card'],
            border_color=colors['border'],
            height=40,
            expand=True,
            on_change=self._filter_categorias,
        )

        return ft.Container(
            content=ft.Column([
                ft.Container(height=15),
                ft.Row([
                    self.categoria_search,
                    ft.Container(
                        content=fab_content,
                        bgcolor=colors['accent'],
                        padding=ft.padding.symmetric(horizontal=20, vertical=12),
                        border_radius=30,
                        on_click=lambda _: self._show_categoria_dialog(),
                    ),
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN, spacing=10),
                ft.Container(height=15),
                self.lista_categorias,
            ], expand=True, spacing=0),
            padding=20,
            expand=True,
        )

    def _build_productos_tab(self):
        colors = _colors(self.page)
        fab_content = ft.Row([
            ft.Icon(ft.Icons.ADD_BOX, size=20),
            ft.Text("Nuevo Producto" if not self.is_mobile else "Nuevo", weight=ft.FontWeight.BOLD),
        ], alignment=ft.MainAxisAlignment.CENTER, spacing=8)

        # Search field for productos
        self.producto_search = ft.TextField(
            hint_text="Buscar productos...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=10,
            bgcolor=colors['card'],
            border_color=colors['border'],
            height=40,
            expand=True,
            on_change=self._filter_productos,
        )

        return ft.Container(
            content=ft.Column([
                ft.Container(height=15),
                ft.Row([
                    self.producto_search,
                    ft.Container(
                        content=fab_content,
                        bgcolor=colors['success'],
                        padding=ft.padding.symmetric(horizontal=20, vertical=12),
                        border_radius=30,
                        on_click=lambda _: self._show_producto_dialog(),
                    ),
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN, spacing=10),
                ft.Container(height=15),
                self.lista_productos,
            ], expand=True, spacing=0),
            padding=20,
            expand=True,
        )

    def _show_categoria_dialog(self, categoria=None):
        colors = _colors(self.page)
        self.selected_image_path = None
        is_mobile = self.page.width < 600
        
        nombre_field = ft.TextField(
            label="Nombre",
            value=categoria.nombre if categoria else "", 
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            prefix_icon=ft.Icons.CATEGORY,
            capitalization=ft.TextCapitalization.WORDS,
            expand=is_mobile,
        )
        
        descripcion_field = ft.TextField(
            label="Descripción", 
            value=categoria.descripcion if categoria else "", 
            multiline=True, 
            max_length=255, 
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            min_lines=2,
            max_lines=4,
            prefix_icon=ft.Icons.DESCRIPTION,
            expand=is_mobile,
        )
        
        colores = [
            ("#2196F3", "Azul"),
            ("#F44336", "Rojo"),
            ("#4CAF50", "Verde"),
            ("#FF9800", "Naranja"),
            ("#9C27B0", "Morado"),
            ("#00BCD4", "Cyan"),
            ("#E91E63", "Rosa"),
            ("#795548", "Marrón"),
        ]
        
        color_options = [ft.dropdown.Option(c[0], c[1]) for c in colores]
        color_dropdown = ft.Dropdown(
            label="Color",
            options=color_options,
            value=categoria.color if categoria else "#2196F3",
            border=ft.InputBorder.OUTLINE,
            border_radius=10,
            prefix_icon=ft.Icons.PALETTE,
            expand=True,
        )
        
        color_preview = ft.Row(
            controls=[
                ft.GestureDetector(
                    content=ft.Container(
                        width=30 if is_mobile else 35,
                        height=30 if is_mobile else 35,
                        bgcolor=c[0],
                        border_radius=20,
                        border=ft.border.all(2, colors['white'] if c[0] == color_dropdown.value else "transparent"),
                    ),
                    on_tap=lambda e, color=c[0]: self._update_color_preview(color, color_preview, color_dropdown),
                )
                for c in colores
            ],
            spacing=6 if is_mobile else 8,
            wrap=True,
        )
        
        activo_sw = ft.Switch(
            label="Activa",
            value=categoria.activo if categoria else True,
            active_color=colors['success'],
        )

        def save_click(e):
            if not nombre_field.value or not nombre_field.value.strip():
                nombre_field.error_text = "Requerido"
                nombre_field.update()
                return
            self._save_categoria(
                nombre_field.value.strip(), 
                descripcion_field.value.strip(), 
                color_dropdown.value, 
                activo_sw.value, 
                categoria.id if categoria else None
            )
            self._close_dialog()

        dialog_content = ft.Column([
            nombre_field,
            color_dropdown,
            color_preview,
            descripcion_field,
            ft.Divider(height=15, color=colors['border']),
            activo_sw,
        ], spacing=12 if is_mobile else 18, tight=True, scroll=ft.ScrollMode.AUTO)

        # ✅ CORREGIDO: Sin fullscreen, usar width=None en móvil
        self.active_dialog = ft.AlertDialog(
            title=ft.Row([
                ft.Icon(ft.Icons.CATEGORY, color=colors['accent'], size=24 if is_mobile else 28),
                ft.Text(
                    "Categoría" if is_mobile else "Gestionar Categoría",
                    weight=ft.FontWeight.BOLD,
                    size=16 if is_mobile else 18,
                ),
            ], spacing=8),
            content=ft.Container(
                content=dialog_content,
                width=None if is_mobile else 450,  # ✅ None para ancho automático en móvil
                padding=5,
            ),
            actions=[
                ft.TextButton("Cancelar", on_click=self._close_dialog),
                ft.ElevatedButton(
                    "Guardar", 
                    on_click=save_click,
                    bgcolor=colors['accent'],
                    color=colors['white'],
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
            # ✅ fullscreen ELIMINADO
)
         
        self._add_to_overlay(self.active_dialog)
    
    def _update_color_preview(self, color, preview_row, dropdown=None):
        colors = _colors(self.page)
        if dropdown:
            dropdown.value = color
        for ctrl in preview_row.controls:
            container = ctrl.content
            container.border = ft.border.all(2, colors['white'] if container.bgcolor == color else "transparent")
        preview_row.update()
        if dropdown:
            dropdown.update()

    def _show_producto_dialog(self, producto=None):
        colors = _colors(self.page)
        db = next(get_db_adaptive())
        try:
            categorias = db.query(Categoria).filter(Categoria.activo == True).all()
            if not categorias:
                show_warning("Cree al menos una categoría")
                return

            nuevo_codigo = ""
            if not producto:
                try:
                    todos_productos = db.query(Producto).filter(Producto.activo == True).all()
                    codigos_numericos = []
                    for p in todos_productos:
                        if p.codigo and str(p.codigo).strip().isdigit():
                            codigos_numericos.append(int(p.codigo))
                    
                    if codigos_numericos:
                        ultimo_numero = max(codigos_numericos)
                        siguiente_numero = ultimo_numero + 1
                        longitud = 4
                        for p in todos_productos:
                            if p.codigo and str(p.codigo).strip().isdigit():
                                longitud = max(longitud, len(str(p.codigo)))
                        nuevo_codigo = str(siguiente_numero).zfill(longitud)
                    else:
                        nuevo_codigo = "0001"
                except Exception as ex:
                    from usr.error_handler import show_error
                    show_error("Error generating code", ex, "configuracion_view._on_guardar_producto")
                    nuevo_codigo = "0001"
            else:
                nuevo_codigo = producto.codigo

            is_mobile = self.page.width < 600

            nombre_field = ft.TextField(
                label="Nombre",
                value=producto.nombre if producto else "", 
                expand=True,
                border=ft.InputBorder.OUTLINE,
                border_radius=10,
                prefix_icon=ft.Icons.INVENTORY_2,
                capitalization=ft.TextCapitalization.WORDS,
            )
            
            codigo_field = ft.TextField(
                label="Código",
                value=nuevo_codigo, 
                expand=True,
                border=ft.InputBorder.OUTLINE,
                border_radius=10,
                prefix_icon=ft.Icons.QR_CODE,
                helper_text="Auto" if not producto else "",
                read_only=not producto,
            )
            
            cat_options = [ft.dropdown.Option(str(c.id), c.nombre) for c in categorias]
            cat_dropdown = ft.Dropdown(
                label="Categoría",
                options=cat_options,
                value=str(producto.categoria_id) if producto else str(categorias[0].id),
                expand=True,
                border=ft.InputBorder.OUTLINE,
                border_radius=10,
                prefix_icon=ft.Icons.CATEGORY,
            )
            
            stock_min_field = ft.TextField(
                label="Stock Mín.",
                value=str(producto.stock_minimo) if producto else "5", 
                keyboard_type=ft.KeyboardType.NUMBER, 
                expand=True,
                border=ft.InputBorder.OUTLINE,
                border_radius=10,
                prefix_icon=ft.Icons.WARNING,
            )
            
            unidad_field = ft.TextField(
                label="Unidad",
                value=producto.unidad_medida if producto else "unidad", 
                expand=True,
                border=ft.InputBorder.OUTLINE,
                border_radius=10,
                prefix_icon=ft.Icons.SCALE,
            )
            
            es_pesable_sw = ft.Switch(
                label="Usa balanza",
                value=getattr(producto, 'es_pesable', False) if producto else False,
                active_color=colors['warning'],
            )
            
            activo_sw = ft.Switch(
                label="Habilitado",
                value=producto.activo if producto else True,
                active_color=colors['success'],
            )

            def save_prod_click(e):
                if not nombre_field.value or not nombre_field.value.strip():
                    nombre_field.error_text = "Requerido"
                    nombre_field.update()
                    return
                if not codigo_field.value or not codigo_field.value.strip():
                    codigo_field.error_text = "Requerido"
                    codigo_field.update()
                    return
                try:
                    self._save_producto(
                        nombre_field.value.strip(), 
                        codigo_field.value.strip(), 
                        "", 
                        int(cat_dropdown.value), 
                        False, 
                        0.0, 
                        unidad_field.value.strip(), 
                        float(stock_min_field.value or 0), 
                        activo_sw.value, 
                        producto.id if producto else None, 
                        es_pesable_sw.value
                    )
                    show_success("Producto guardado correctamente")
                    self._close_dialog()
                    if hasattr(self, '_load_data'):
                        self._load_data()
                except Exception as ex:
                    from usr.error_handler import show_error
                    show_error("Error saving product", ex, "configuracion_view._on_guardar_producto")
                    show_error(f"Error: {str(ex)}")

            if is_mobile:
                content_column = ft.Column([
                    nombre_field,
                    codigo_field,
                    cat_dropdown,
                    stock_min_field,
                    unidad_field,
                    ft.Divider(height=15, color=colors['border']),
                    es_pesable_sw,
                    activo_sw,
                ], spacing=12, tight=True, scroll=ft.ScrollMode.AUTO)
            else:
                content_column = ft.Column([
                    ft.Row([nombre_field, codigo_field], spacing=15),
                    cat_dropdown,
                    ft.Row([stock_min_field, unidad_field], spacing=15),
                    ft.Divider(height=20, color=colors['border']),
                    es_pesable_sw,
                    activo_sw,
                ], spacing=15, tight=True)

            # ✅ CORREGIDO: Sin fullscreen
            self.active_dialog = ft.AlertDialog(
                title=ft.Row([
                    ft.Icon(ft.Icons.INVENTORY_2, color=colors['success'], size=24 if is_mobile else 28),
                    ft.Text(
                        "Producto" if is_mobile else "Ficha de Producto",
                        weight=ft.FontWeight.BOLD,
                        size=16 if is_mobile else 18,
                    ),
                ], spacing=8),
                content=ft.Container(
                    content=content_column,
                    width=None if is_mobile else 550,  # ✅ None para móvil
                    padding=5,
                ),
                actions=[
                    ft.TextButton("Cancelar", on_click=self._close_dialog),
                    ft.ElevatedButton(
                        "Guardar", 
                        on_click=save_prod_click, 
                        bgcolor=colors['success'], 
                        color=colors['white'],
                    ),
                ],
                actions_alignment=ft.MainAxisAlignment.END,
                # ✅ fullscreen ELIMINADO
            )
            
            self._add_to_overlay(self.active_dialog)
        finally:
            db.close()

    def _save_categoria(self, nombre, descripcion, color, activo, cat_id):
        from datetime import datetime
        from usr.database.sync_queue import get_sync_queue
        
        # 1. Preparar data con tipos correctos
        cat_data = {
            "nombre": str(nombre),
            "descripcion": str(descripcion) if descripcion else "",
            "color": str(color),
            "activo": 1 if activo else 0,
            "updated_at": datetime.now().isoformat()
        }
        if cat_id:
            cat_data["id"] = cat_id
        
        # 2. Guardar local en SQLite (siempre)
        try:
            LocalReplica.save_categorias([cat_data])
        except Exception as e:
            print(f"❌ Error SQLite: {e}")
        
        # 3. Agregar a la cola de sync (se procesará cuando haya internet)
        try:
            queue = get_sync_queue()
            queue.add_pending('categorias', 'insert', cat_data)
            # Intentar sync inmediato si hay conexión
            self._trigger_sync()
        except Exception as e:
            from usr.error_handler import show_error
            show_error("Error al agregar categoría a cola de sync", e, "configuracion_view._on_guardar_categoria")
        
        show_success("Categoría guardada")
        
        self._close_dialog()
        self._load_data()

    def _save_producto(self, n, c, d, cat_id, rf, pu, u, sm, a, p_id, es_p=False):
        from datetime import datetime
        from usr.database.sync_queue import get_sync_queue
        
        # 1. Preparar data con tipos correctos para Postgres
        prod_data = {
            "nombre": str(n),
            "codigo": str(c),
            "descripcion": str(d) if d else "",
            "categoria_id": int(cat_id) if cat_id else None,
            "requiere_foto_peso": 1 if rf else 0,
            "peso_unitario": float(pu) if pu else 0.0,
            "stock_minimo": float(sm) if sm else 0.0,
            "stock_actual": 0,
            "unidad_medida": str(u) if u else "unidad",
            "activo": 1 if a else 0,
            "es_pesable": 1 if es_p else 0,
            "almacen_predeterminado": "principal",
            "updated_at": datetime.now().isoformat()
        }
        if p_id:
            prod_data["id"] = p_id
        
        # 2. Guardar local en SQLite (siempre)
        try:
            LocalReplica.save_productos([prod_data])
        except Exception as e:
            print(f"❌ Error SQLite: {e}")
        
        # 3. Agregar a la cola de sync (se procesará cuando haya internet)
        try:
            queue = get_sync_queue()
            queue.add_pending('productos', 'insert', prod_data)
            # Intentar sync inmediato si hay conexión
            self._trigger_sync()
        except:
            pass
        
        show_success("Guardado")
        
        self._close_dialog()
        self._load_data()
        return True

    def _confirm_delete(self, objeto, tipo="producto"):
        colors = _colors(self.page)
        color = colors['error'] if tipo == "producto" else "#ff9800"
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Row([
                ft.Icon(ft.Icons.WARNING, color=colors['error']),
                ft.Text(f"Eliminar {tipo.capitalize()}", weight=ft.FontWeight.BOLD),
            ], spacing=10),
            content=ft.Column([
                ft.Text(
                    f"¿Está seguro que desea eliminar '{objeto.nombre}'?",
                    size=15,
                ),
                ft.Text(
                    "Esto lo desactivará del catálogo pero mantendrá el historial.",
                    size=12,
                    color=colors['text_secondary'],
                    italic=True,
                ),
            ], spacing=10),
            actions=[
                ft.TextButton("Cancelar", on_click=self._close_dialog),
                ft.ElevatedButton(
                    "Eliminar", 
                    color=colors['white'],
                    bgcolor=color,
                    on_click=lambda _: self._delete_logic(objeto, tipo),
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
)
        
        self._add_to_overlay(self.active_dialog)
    
    def _delete_logic(self, objeto, tipo):
        from datetime import datetime
        from usr.database.sync_queue import get_sync_queue
        from usr.database.local_replica import LocalReplica
        
        db = next(get_db_adaptive())
        try:
            if tipo == "producto":
                item = db.query(Producto).get(objeto.id)
            else:
                item = db.query(Categoria).get(objeto.id)
            
            if tipo == "producto":
                item.activo = False
                db.commit()
                
                # Guardar en local
                LocalReplica.save_productos([{
                    'id': item.id,
                    'nombre': item.nombre,
                    'codigo': item.codigo,
                    'descripcion': item.descripcion,
                    'categoria_id': item.categoria_id,
                    'es_pesable': item.es_pesable,
                    'requiere_foto_peso': item.requiere_foto_peso,
                    'peso_unitario': item.peso_unitario,
                    'unidad_medida': item.unidad_medida,
                    'stock_actual': item.stock_actual,
                    'stock_minimo': item.stock_minimo,
                    'activo': 0,
                    'updated_at': datetime.now().isoformat(),
                    'almacen_predeterminado': item.almacen_predeterminado
                }])
                
                # Agregar a cola de sync
                try:
                    queue = get_sync_queue()
                    queue.add_pending('productos', 'update', {
                        'id': item.id,
                        'activo': 0,
                        'updated_at': datetime.now().isoformat()
                    })
                    self._trigger_sync()
                except:
                    pass
                    
            else:  # categoria
                item.activo = False
                db.commit()
                
                # Guardar en local
                LocalReplica.save_categorias([{
                    'id': item.id,
                    'nombre': item.nombre,
                    'descripcion': item.descripcion,
                    'color': item.color,
                    'activo': 0,
                    'updated_at': datetime.now().isoformat()
                }])
                
                # Agregar a cola de sync
                try:
                    queue = get_sync_queue()
                    queue.add_pending('categorias', 'update', {
                        'id': item.id,
                        'activo': 0,
                        'updated_at': datetime.now().isoformat()
                    })
                    self._trigger_sync()
                except Exception as e:
                    from usr.error_handler import show_error
                    show_error("Error al actualizar categoría en cola de sync", e, "configuracion_view._on_toggle_categoria")
            
            show_success(f"{tipo.capitalize()} desactivado correctamente")
            self._load_data()
            self._close_dialog()
        except Exception as e:
            show_error(f"Error: {str(e)}")
        finally:
            db.close()
    
    def _load_data(self):
        colors = _colors(self.page)
        self.is_mobile = self.page.width < 768 if self.page else False
        
        try:
            db = next(get_db_adaptive())
            cats = db.query(Categoria).filter(Categoria.activo == True).all()
            prods = db.query(Producto).filter(Producto.activo == True).options(
                joinedload(Producto.categoria)
            ).all()
            
            self.categorias_cache = cats
            self.productos_cache = prods
            
            if self.is_mobile:
                self.lista_categorias.controls = [self._create_categoria_item_mobile(c) for c in cats]
            else:
                self.lista_categorias.controls = self._create_categoria_grid(cats)
            
            self.lista_productos.controls = [self._create_producto_item(p) for p in prods]
            
            # Cargar proveedores desde SQLite local
            self._load_proveedores()
            
            self.update()
            db.close()
        except Exception as e:
            show_error(f"Error al cargar datos: {str(e)}")
            if db:
                db.close()
    
    def _filter_categorias(self, e=None):
        if not hasattr(self, 'categorias_cache'):
            return
        search = self.categoria_search.value.lower() if self.categoria_search.value else ""
        filtered = [c for c in self.categorias_cache if search in c.nombre.lower()]
        if self.is_mobile:
            self.lista_categorias.controls = [self._create_categoria_item_mobile(c) for c in filtered]
        else:
            self.lista_categorias.controls = self._create_categoria_grid(filtered)
        self.update()

    def _filter_productos(self, e=None):
        if not hasattr(self, 'productos_cache'):
            return
        search = self.producto_search.value.lower() if self.producto_search.value else ""
        filtered = [p for p in self.productos_cache if search in p.nombre.lower()]
        self.lista_productos.controls = [self._create_producto_item(p) for p in filtered]
        self.update()

    def _create_categoria_grid(self, categorias):
        """Grid de 2 columnas solo para desktop"""
        colors = _colors(self.page)
        grid_items = []
        
        # ✅ Crear pares de categorías para filas de 2 columnas
        for i in range(0, len(categorias), 2):
            row_controls = []
            
            # Primera columna
            if i < len(categorias):
                row_controls.append(self._create_categoria_card(categorias[i]))
            
            # Segunda columna (si existe)
            if i + 1 < len(categorias):
                row_controls.append(self._create_categoria_card(categorias[i + 1]))
            
            # ✅ Si hay solo 1 item en la fila, agregar espacio vacío
            if len(row_controls) == 1:
                row_controls.append(ft.Container(expand=True))
            
            # ✅ Crear fila con expand=True para desktop
            grid_items.append(
                ft.Row(row_controls, spacing=15, expand=True)
            )
        
        return grid_items

    def _create_categoria_card(self, c):
        """Card de categoría para desktop - 2 columnas"""
        colors = _colors(self.page)
        return ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(
                        content=ft.Icon(ft.Icons.CATEGORY, color=colors['white'], size=28),
                        bgcolor=c.color,
                        padding=12,
                        border_radius=12,
                    ),
                    ft.Column([
                        ft.Text(c.nombre, weight=ft.FontWeight.BOLD, size=15, color=colors['text_primary']),
                        ft.Text(
                            c.descripcion or "Sin descripción", 
                            size=12, 
                            color=colors['text_secondary'], 
                            max_lines=1, 
                            overflow=ft.TextOverflow.ELLIPSIS,
                        ),
                    ], expand=True, spacing=2),
                ], alignment=ft.MainAxisAlignment.START),
                ft.Divider(height=1, color=colors['border']),
                ft.Row([
                    ft.Container(
                        content=ft.Row([
                            ft.Icon(ft.Icons.CIRCLE, size=8, color=colors['success'] if c.activo else "#9E9E9E"),
                            ft.Text("Activo" if c.activo else "Inactivo", size=11, color=colors['text_secondary']),
                        ], spacing=5),
                    ),
                    ft.Row([
                        ft.IconButton(
                            ft.Icons.EDIT, 
                            icon_size=18,
                            on_click=lambda _, cat=c: self._show_categoria_dialog(cat),
                        ),
                        ft.IconButton(
                            ft.Icons.DELETE, 
                            icon_size=18,
                            on_click=lambda _, cat=c: self._confirm_delete(cat, "categoria"),
                        ),
                    ], spacing=0),
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            ], spacing=10),
            padding=15,
            bgcolor=colors['card'],
            border_radius=15,
            border=ft.border.all(1, colors['border']),
            expand=True,  # ✅ Solo en desktop
        )

    def _create_categoria_item_mobile(self, c):
        """Item de categoría para móvil - 1 sola columna"""
        colors = _colors(self.page)
        return ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(
                        content=ft.Icon(ft.Icons.CATEGORY, color=colors['white'], size=24),
                        bgcolor=c.color,
                        padding=10,
                        border_radius=10,
                    ),
                    ft.Column([
                        ft.Text(c.nombre, weight=ft.FontWeight.BOLD, size=14, color=colors['text_primary']),
                        ft.Text(
                            c.descripcion or "Sin descripción", 
                            size=11, 
                            color=colors['text_secondary'], 
                            max_lines=1, 
                            overflow=ft.TextOverflow.ELLIPSIS,
                        ),
                    ], expand=True, spacing=1),
                ], alignment=ft.MainAxisAlignment.START),
                ft.Row([
                    ft.Container(
                        content=ft.Row([
                            ft.Icon(ft.Icons.CIRCLE, size=6, color=colors['success'] if c.activo else "#9E9E9E"),
                            ft.Text("Activo" if c.activo else "Inactivo", size=10, color=colors['text_secondary']),
                        ], spacing=4),
                    ),
                    ft.Row([
                        ft.IconButton(
                            ft.Icons.EDIT, 
                            icon_size=20,  # ✅ Más grande para touch
                            padding=5,
                            on_click=lambda _, cat=c: self._show_categoria_dialog(cat),
                        ),
                        ft.IconButton(
                            ft.Icons.DELETE, 
                            icon_size=20,  # ✅ Más grande para touch
                            padding=5,
                            on_click=lambda _, cat=c: self._confirm_delete(cat, "categoria"),
                        ),
                    ], spacing=0),
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            ], spacing=8),
            padding=15,  # ✅ Más padding para touch
            bgcolor=colors['card'],
            border_radius=12,
            border=ft.border.all(1, colors['border']),
            # ✅ NO usar expand=True en móvil para evitar deformaciones
            width=None,  
        )

    def _create_producto_item(self, p):
        colors = _colors(self.page)
        tag = ft.Container(
            content=ft.Text("PESABLE", size=9, weight=ft.FontWeight.BOLD, color=colors['white']),
            bgcolor=colors['warning'],
            padding=ft.padding.symmetric(horizontal=6, vertical=2),
            border_radius=4,
        ) if getattr(p, 'es_pesable', False) else None

        return ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(
                        content=ft.Icon(ft.Icons.INVENTORY_2, color=colors['white'], size=24),
                        bgcolor=colors['accent'],
                        padding=10,
                        border_radius=10,
                    ),
                    ft.Column([
                        ft.Row([
                            ft.Text(p.nombre, weight=ft.FontWeight.BOLD, size=14, color=colors['text_primary']),
                            tag if tag else ft.Container(),
                        ], spacing=8),
                        ft.Text(
                            f"Cat: {p.categoria.nombre if p.categoria else 'N/A'} • SKU: {p.codigo}",
                            size=11, 
                            color=colors['text_secondary'],
                        ),
                    ], expand=True, spacing=2),
                ], alignment=ft.MainAxisAlignment.START),
                ft.Row([
                    ft.Row([
                        ft.Icon(ft.Icons.LIST, size=14, color=colors['text_secondary']),
                        ft.Text(f"Mín: {p.stock_minimo} {p.unidad_medida}", size=11, color=colors['text_secondary']),
                    ], spacing=5),
                    ft.Row([
                        ft.IconButton(
                            ft.Icons.EDIT, 
                            icon_size=18,
                            on_click=lambda _, prod=p: self._show_producto_dialog(prod),
                        ),
                        ft.IconButton(
                            ft.Icons.DELETE, 
                            icon_size=18,
                            on_click=lambda _, prod=p: self._confirm_delete(prod, "producto"),
                        ),
                    ], spacing=0),
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            ], spacing=8),
            padding=12,
            bgcolor=colors['card'],
            border_radius=12,
            border=ft.border.all(1, colors['border']),
        )

    def _close_dialog(self, e=None):
        if not self.page:
            return
        
        # Cerrar todos los AlertDialog en overlay
        for control in self.page.overlay[:]:
            if isinstance(control, ft.AlertDialog):
                control.open = False
        
        # También cerrar active_dialog si existe
        if self.active_dialog:
            self.active_dialog.open = False
        
        # Actualizar la página
        self.page.update()
        
        # Limpiar referencia
        self.active_dialog = None    

    def _add_to_overlay(self, control):
        if self.page:
            if isinstance(control, ft.AlertDialog):
                control.open = True
                if control not in self.page.overlay:
                    self.page.overlay.append(control)
            else:
                if control not in self.page.overlay:
                    self.page.overlay.append(control)
            self.page.update()

    def _remove_from_overlay(self, control):
        if self.page and control in self.page.overlay:
            self.page.overlay.remove(control)
    
    # ==================== PROVEEDORES ====================
    
    def _build_proveedores_tab(self):
        colors = _colors(self.page)
        fab_content = ft.Row([
            ft.Icon(ft.Icons.ADD, size=20),
            ft.Text("Nuevo Proveedor" if not self.is_mobile else "Nuevo", weight=ft.FontWeight.BOLD),
        ], alignment=ft.MainAxisAlignment.CENTER, spacing=8)
        
        self.proveedor_search = ft.TextField(
            hint_text="Buscar proveedores...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=10,
            bgcolor=colors['card'],
            border_color=colors['border'],
            height=40,
            expand=True,
            on_change=self._filter_proveedores,
        )
        
        self.lista_proveedores = ft.GridView(
            expand=True,
            runs_count=1 if self.is_mobile else 3,
            spacing=10,
            padding=20,
        )
        
        return ft.Container(
            content=ft.Column([
                ft.Container(height=15),
                ft.Row([
                    self.proveedor_search,
                    ft.Container(
                        content=fab_content,
                        bgcolor=colors['accent'],
                        padding=ft.padding.symmetric(horizontal=20, vertical=12),
                        border_radius=30,
                        on_click=lambda _: self._show_proveedor_dialog(),
                    ),
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN, spacing=10),
                ft.Container(height=15),
                self.lista_proveedores,
            ], expand=True, spacing=0),
            padding=20,
            expand=True,
        )
    
    def _show_proveedor_dialog(self, proveedor=None):
        colors = _colors(self.page)
        
        nombre_input = ft.TextField(
            label="Nombre *", 
            value=proveedor.get('nombre', '') if proveedor else '',
            border_radius=10
        )
        rif_input = ft.TextField(
            label="RIF",
            value=proveedor.get('rif', '') if proveedor else '',
            border_radius=10
        )
        telefono_input = ft.TextField(
            label="Teléfono",
            value=proveedor.get('telefono', '') if proveedor else '',
            border_radius=10
        )
        email_input = ft.TextField(
            label="Email",
            value=proveedor.get('email', '') if proveedor else '',
            border_radius=10
        )
        direccion_input = ft.TextField(
            label="Dirección",
            value=proveedor.get('direccion', '') if proveedor else '',
            border_radius=10,
            multiline=True,
            min_lines=2
        )
        contacto_input = ft.TextField(
            label="Persona de contacto",
            value=proveedor.get('contacto', '') if proveedor else '',
            border_radius=10
        )
        observaciones_input = ft.TextField(
            label="Observaciones",
            value=proveedor.get('observaciones', '') if proveedor else '',
            border_radius=10,
            multiline=True,
            min_lines=2
        )
        estado_switch = ft.Switch(
            label="Activo",
            value=proveedor.get('estado', 'Activo') == 'Activo' if proveedor else True,
        )
        
        prov_id = proveedor.get('id') if proveedor else None
        
        def on_guardar(e):
            if not nombre_input.value.strip():
                return
            self._save_proveedor(
                nombre_input.value.strip(),
                rif_input.value.strip(),
                telefono_input.value.strip(),
                email_input.value.strip(),
                direccion_input.value.strip(),
                contacto_input.value.strip(),
                observaciones_input.value.strip(),
                estado_switch.value,
                prov_id
            )
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Text(f"{'Editar' if proveedor else 'Nuevo'} Proveedor"),
            content=ft.Column([
                nombre_input, rif_input, telefono_input, email_input,
                direccion_input, contacto_input, observaciones_input, estado_switch
            ], tight=True, scroll=ft.ScrollMode.AUTO),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Guardar", on_click=on_guardar, bgcolor=colors['accent']),
            ]
        )
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()
    
    def _save_proveedor(self, nombre, rif, telefono, email, direccion, contacto, observaciones, activo, prov_id):
        from datetime import datetime
        from usr.database.sync_queue import get_sync_queue
        
        prov_data = {
            "nombre": str(nombre),
            "rif": str(rif) if rif else None,
            "telefono": str(telefono) if telefono else None,
            "email": str(email) if email else None,
            "direccion": str(direccion) if direccion else None,
            "contacto": str(contacto) if contacto else None,
            "observaciones": str(observaciones) if observaciones else None,
            "estado": "Activo" if activo else "Inactivo",
            "updated_at": datetime.now().isoformat()
        }
        if prov_id:
            prov_data["id"] = prov_id
        
        # Guardar local
        try:
            LocalReplica.save_proveedores([prov_data])
        except Exception as e:
            print(f"❌ Error SQLite: {e}")
        
        # Sync queue
        try:
            queue = get_sync_queue()
            queue.add_pending('proveedores', 'insert', prov_data)
            self._trigger_sync()
        except Exception as e:
            from usr.error_handler import show_error
            show_error("Error al agregar proveedor a sync", e, "configuracion_view._save_proveedor")
        
        show_success("Proveedor guardado")
        self._close_dialog()
        self._load_proveedores()
    
    def _load_proveedores(self):
        from usr.database.local_replica import LocalReplica
        self.proveedores_data = LocalReplica.get_proveedores()
        self._render_proveedores(self.proveedores_data)
    
    def _render_proveedores(self, data):
        colors = _colors(self.page)
        self.lista_proveedores.controls = []
        
        for prov in data:
            card = ft.Container(
                content=ft.Column([
                    ft.Row([
                        ft.Icon(ft.Icons.LOCAL_SHIPPING, color=colors['accent']),
                        ft.Text(prov.get('nombre', 'Sin nombre'), weight="bold", expand=True),
                        ft.Container(
                            content=ft.Text(prov.get('estado', 'Activo'), size=10, color="white"),
                            bgcolor=colors['success'] if prov.get('estado') == 'Activo' else colors['error'],
                            padding=ft.padding.symmetric(horizontal=8, vertical=2),
                            border_radius=10
                        )
                    ]),
                    ft.Divider(height=10),
                    ft.Text(prov.get('rif', 'Sin RIF'), size=11, color=colors['text_secondary']),
                    ft.Text(prov.get('telefono', 'Sin teléfono'), size=11, color=colors['text_secondary']),
                    ft.Text(prov.get('email', 'Sin email'), size=11, color=colors['text_secondary']),
                ], spacing=2),
                padding=15,
                bgcolor=colors['card'],
                border_radius=10,
                ink=True,
                on_click=lambda _, p=prov: self._show_proveedor_dialog(p)
            )
            self.lista_proveedores.controls.append(card)
        
        self.page.update()
    
    def _filter_proveedores(self, e):
        search = self.proveedor_search.value.lower()
        if not search:
            self._render_proveedores(self.proveedores_data)
            return
        
        filtered = [p for p in self.proveedores_data 
                   if search in (p.get('nombre') or '').lower() 
                   or search in (p.get('rif') or '').lower()]
        self._render_proveedores(filtered)
    
    # ==================== FIN PROVEEDORES ====================
    
    def _build_sistema_tab(self):
        colors = _colors(self.page)
        return ft.Container(
            content=ft.Column([
                ft.Container(height=20),
                ft.Card(
                    content=ft.Container(
                        content=ft.Column([
                            # --- SECCIÓN DE DIAGNÓSTICO (Existente) ---
                            ft.Row([
                                ft.Container(
                                    content=ft.Icon(ft.Icons.DASHBOARD, color=colors['white'], size=28),
                                    bgcolor=colors['accent_dark'],
                                    padding=12,
                                    border_radius=12,
                                ),
                                ft.Column([
                                    ft.Text("Mantenimiento del Sistema", weight=ft.FontWeight.BOLD, size=16),
                                    ft.Text("Herramientas de diagnóstico y configuración", size=12, color=colors['text_secondary']),
                                ], spacing=2),
                            ], spacing=15),
                            ft.Divider(height=20, color=colors['border']),
                            
                            ft.Text(
                                "Si experimenta errores tras actualizaciones o cambios de configuración, use 'Probar Conexión' para verificar la base de datos.",
                                size=13,
                                color="#424242",
                            ),
                            ft.ElevatedButton(
                                "Probar Conexión", 
                                on_click=self._test_connection_action,
                                icon=ft.Icons.STORAGE,
                                bgcolor="#7B1FA2",
                                color=colors['white'],
                            ),

                            # --- NUEVA SECCIÓN: NOTIFICACIONES PUSH (2026 Fix) ---
                            ft.Divider(height=20, color=colors['border']),
                            ft.Text(
                                "Configuración de Alertas", 
                                weight=ft.FontWeight.BOLD, 
                                size=14
                            ),
                            ft.Text(
                                "Habilite las notificaciones para recibir alertas de stock bajo y validaciones en tiempo real.",
                                size=12,
                                color=colors['text_secondary'],
                            ),
                            ft.ElevatedButton(
                                "Habilitar Notificaciones", 
                                on_click=self._request_notifications_action,
                                icon=ft.Icons.NOTIFICATIONS_ACTIVE,
                                bgcolor=colors['accent_dark'],
                                color=colors['white'],
                            ),

                            ft.Container(
                                content=self.test_result_text,
                                padding=10,
                                bgcolor=colors['bg'],
                                border_radius=8,
                                visible=False,
                            ),
                            
                            # --- NUEVA SECCIÓN: MODO OFFLINE ---
                            ft.Divider(height=30, color=colors['border']),
                            ft.Text(
                                "Modo Offline", 
                                weight=ft.FontWeight.BOLD, 
                                size=14
                            ),
                            ft.Text(
                                "Active el modo offline para usar la aplicación sin conexión a internet. Los datos se guardarán localmente y se sincronizarán al reconectar.",
                                size=12,
                                color=colors['text_secondary'],
                            ),
                            ft.Container(height=10),
                            ft.Row([
                                ft.Text("Estado:", size=14, color=colors['text_secondary']),
                                self.offline_status_indicator,
                            ], spacing=10),
                            ft.Container(height=10),
                            ft.ElevatedButton(
                                "Cambiar Modo", 
                                on_click=self._toggle_offline_mode,
                                icon=ft.Icons.WIFI_OFF,
                                bgcolor=colors['accent'],
                                color=colors['white'],
                            ),
                            
                            ft.Divider(height=30, color=colors['border']),
                            
                            ft.Text(
                                "Gestion de Operador", 
                                weight=ft.FontWeight.BOLD, 
                                size=14
                            ),
                            ft.Text(
                                "Cambie el operador registrado en este dispositivo.",
                                size=12,
                                color=colors['text_secondary'],
                            ),
                            ft.Container(height=10),
                            ft.ElevatedButton(
                                "Cambiar operador de este dispositivo", 
                                on_click=self._on_cambiar_operador,
                                icon=ft.Icons.PERSON_OUTLINED,
                                bgcolor=ft.Colors.ORANGE_600,
                                color=ft.Colors.WHITE,
                            ),
                        ], spacing=15),
                        padding=25,
                    ),
                ),
            ], spacing=10, scroll=ft.ScrollMode.AUTO, expand=True),
            padding=20,
            expand=True,
        )
    
    def _on_cambiar_operador(self, e):
        from usr.database.local_replica import LocalReplica
        
        usuario = LocalReplica.get_usuario_dispositivo()
        
        if usuario and usuario.get("pin_hash"):
            self.pin_verify_input = ft.TextField(
                label="PIN actual",
                password=True,
                max_length=4,
                keyboard_type=ft.KeyboardType.NUMBER
            )
            
            self.verify_dialog = ft.AlertDialog(
                title=ft.Text("Verificar PIN"),
                content=ft.Column([
                    ft.Text("Ingrese su PIN actual para continuar"),
                    self.pin_verify_input,
                ], tight=True),
                actions=[
                    ft.TextButton("Cancelar", on_click=self._close_dialog),
                    ft.ElevatedButton("Verificar", on_click=self._on_verificar_pin_cambio, bgcolor=ft.Colors.DEEP_PURPLE_600, color=ft.Colors.WHITE),
                ]
            )
            self.page.overlay.append(self.verify_dialog)
            self.verify_dialog.open = True
            self.page.update()
        else:
            self._confirmar_cambio()
    
    def _on_verificar_pin_cambio(self, e):
        from usr.database.local_replica import LocalReplica
        
        if not self.pin_verify_input.value:
            return
        if LocalReplica.verificar_pin(self.pin_verify_input.value):
            self._confirmar_cambio()
        else:
            show_error("PIN incorrecto")
    
    def _confirmar_cambio(self):
        from usr.database.local_replica import LocalReplica
        from main import main as restart_main
        
        self._close_dialog()
        LocalReplica.eliminar_usuario_dispositivo()
        show_info("Recargando...")
        self.page.run_task(restart_main, self.page)
    
    def _close_dialog(self, e=None):
        if hasattr(self, 'page') and self.page and self.page.overlay:
            for d in self.page.overlay.copy():
                if hasattr(d, 'open'):
                    d.open = False
            self.page.update()
    
    def _toggle_offline_mode(self, e=None):
        from usr.database import base
        current = base.is_online()
        base._is_online = not current
        
        if current:
            self.offline_status_indicator.value = "📴 FORZADO OFFLINE"
            self.offline_status_indicator.color = ft.Colors.RED_400
            show_warning("Modo offline forzado - Los datos se guardarán localmente")
        else:
            self.offline_status_indicator.value = "🟢 ONLINE"
            self.offline_status_indicator.color = ft.Colors.GREEN_400
            show_success("Conexión normal restaurada")
        
        self.update()

    def _test_connection_action(self, e):
        db = None
        try:
            db = next(get_db_adaptive())
            db.execute(text("SELECT 1"))
            self.test_result_text.value = "✅ Conexión exitosa - Base de datos operativa"
            self.test_result_text.color = "#2E7D32"
            self.test_result_text.visible = True
            show_success("Conexión a base de datos verificada")
        except Exception as ex:
            self.test_result_text.value = f"❌ Error: {str(ex)}"
            self.test_result_text.color = "#c62828"
            self.test_result_text.visible = True
            show_error(f"Error de conexión: {str(ex)}")
        finally:
            if db:
                db.close()
            self.update()

    def refresh(self):
        self.is_mobile = self.page.width < 768 if self.page else False
        self._load_data()
    
    def _request_notifications_action(self, e):
        try:
            # Buscamos el fcm_handler que definimos en el main (app_instance.fcm_handler)
            # Flet permite acceder a la instancia de la página
            if hasattr(self.page, "overlay"):
                # Buscamos el componente Fcm en el overlay de la página
                fcm_component = next((c for c in self.page.overlay if hasattr(c, "request_permission")), None)
                
                if fcm_component:
                    fcm_component.request_permission()
                    show_info("Solicitando permiso de notificaciones...")
                else:
                    show_warning("El servicio de notificaciones no está activo en este entorno.")
            else:
                show_error("No se pudo acceder al sistema de la aplicación.")
                
        except Exception as ex:
            show_error(f"Error al activar notificaciones: {str(ex)}")

    def _trigger_sync(self):
        """Intenta sincronizar inmediatamente si hay conexión."""
        try:
            from usr.database.sync import get_sync_manager
            sync_mgr = get_sync_manager()
            if sync_mgr and sync_mgr.check_connection():
                import threading
                thread = threading.Thread(target=sync_mgr._process_sync_queue, daemon=True)
                thread.start()
                print("[SYNC] Sync inmediato activado")
        except Exception as e:
            print(f"[SYNC] Error al activar sync inmediato: {e}")