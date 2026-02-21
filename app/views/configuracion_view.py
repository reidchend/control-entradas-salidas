import flet as ft
from app.database.base import get_db
from app.models import Categoria, Producto, Movimiento
from sqlalchemy.orm import joinedload
from sqlalchemy import text

class ConfiguracionView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.padding = 0
        self.bgcolor = "#f5f5f5"
        
        self.selected_image_path = None
        self.active_dialog = None
        self.active_snackbar = None
        self.is_mobile = False
        
        self.lista_categorias = ft.Column(expand=True, spacing=12, scroll=ft.ScrollMode.AUTO)
        self.lista_productos = ft.Column(expand=True, spacing=12, scroll=ft.ScrollMode.AUTO)
        self.test_result_text = ft.Text("", size=14, weight=ft.FontWeight.BOLD)
        
        self._build_ui()

    def did_mount(self):
        if self.page:
            self.is_mobile = self.page.width < 768
            self.page.on_resize = self._on_resize
            self._load_data()

    def _on_resize(self, e):
        self.is_mobile = self.page.width < 768
        self.update()

    def _build_ui(self):
        header = ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(
                        content=ft.Icon(ft.Icons.SETTINGS, size=32, color=ft.Colors.WHITE),
                        bgcolor="#1976D2",
                        padding=12,
                        border_radius=12
                    ),
                    ft.Column([
                        ft.Text("Configuración", size=26, weight=ft.FontWeight.BOLD, color="#212121"),
                        ft.Text("Gestione categorías y catálogo de productos", size=13, color="#757575"),
                    ], spacing=2, expand=True),
                ], alignment=ft.MainAxisAlignment.START),
            ], spacing=8),
            padding=ft.padding.only(left=20, right=20, top=20, bottom=15),
            bgcolor=ft.Colors.WHITE,
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
                    text="Sistema", 
                    icon=ft.Icons.DASHBOARD_CUSTOMIZE,
                    content=self._build_sistema_tab(),
                ),
            ],
            expand=True,
        )

        self.content = ft.Column([header, self.tabs], expand=True, spacing=0)

    def _build_categorias_tab(self):
        fab_content = ft.Row([
            ft.Icon(ft.Icons.ADD, size=20),
            ft.Text("Nueva Categoría" if not self.is_mobile else "Nueva", weight=ft.FontWeight.BOLD),
        ], alignment=ft.MainAxisAlignment.CENTER, spacing=8)

        return ft.Container(
            content=ft.Column([
                ft.Container(height=15),
                ft.Row([
                    ft.Container(
                        content=fab_content,
                        bgcolor="#1976D2",
                        padding=ft.padding.symmetric(horizontal=20, vertical=12),
                        border_radius=30,
                        on_click=lambda _: self._show_categoria_dialog(),
                    ),
                ], alignment=ft.MainAxisAlignment.END if not self.is_mobile else ft.MainAxisAlignment.CENTER),
                ft.Container(height=10),
                self.lista_categorias,
            ], expand=True, spacing=0),
            padding=20,
            expand=True,
        )

    def _build_productos_tab(self):
        fab_content = ft.Row([
            ft.Icon(ft.Icons.ADD_BOX, size=20),
            ft.Text("Nuevo Producto" if not self.is_mobile else "Nuevo", weight=ft.FontWeight.BOLD),
        ], alignment=ft.MainAxisAlignment.CENTER, spacing=8)

        return ft.Container(
            content=ft.Column([
                ft.Container(height=15),
                ft.Row([
                    ft.Container(
                        content=fab_content,
                        bgcolor="#388E3C",
                        padding=ft.padding.symmetric(horizontal=20, vertical=12),
                        border_radius=30,
                        on_click=lambda _: self._show_producto_dialog(),
                    ),
                ], alignment=ft.MainAxisAlignment.END if not self.is_mobile else ft.MainAxisAlignment.CENTER),
                ft.Container(height=10),
                self.lista_productos,
            ], expand=True, spacing=0),
            padding=20,
            expand=True,
        )

    def _show_categoria_dialog(self, categoria=None):
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
                        border=ft.border.all(2, "#FFFFFF" if c[0] == color_dropdown.value else "transparent"),
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
            active_color="#388E3C",
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
            ft.Divider(height=15, color="#E0E0E0"),
            activo_sw,
        ], spacing=12 if is_mobile else 18, tight=True, scroll=ft.ScrollMode.AUTO)

        # ✅ CORREGIDO: Sin fullscreen, usar width=None en móvil
        self.active_dialog = ft.AlertDialog(
            title=ft.Row([
                ft.Icon(ft.Icons.CATEGORY, color="#1976D2", size=24 if is_mobile else 28),
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
                    bgcolor="#1976D2",
                    color=ft.Colors.WHITE,
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
            # ✅ fullscreen ELIMINADO
        )
        
        self._add_to_overlay(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _update_color_preview(self, color, preview_row, dropdown=None):
        if dropdown:
            dropdown.value = color
        for ctrl in preview_row.controls:
            container = ctrl.content
            container.border = ft.border.all(2, "#FFFFFF" if container.bgcolor == color else "transparent")
        preview_row.update()
        if dropdown:
            dropdown.update()

    def _show_producto_dialog(self, producto=None):
        db = next(get_db())
        try:
            categorias = db.query(Categoria).filter(Categoria.activo == True).all()
            if not categorias:
                self._show_error("⚠️ Cree al menos una categoría")
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
                    print(f"Error auto-generación: {ex}")
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
                active_color="#F57C00",
            )
            
            activo_sw = ft.Switch(
                label="Habilitado",
                value=producto.activo if producto else True,
                active_color="#388E3C",
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
                    self._close_dialog()
                except Exception as ex:
                    self._show_error(f"Error: {str(ex)}")

            if is_mobile:
                content_column = ft.Column([
                    nombre_field,
                    codigo_field,
                    cat_dropdown,
                    stock_min_field,
                    unidad_field,
                    ft.Divider(height=15, color="#E0E0E0"),
                    es_pesable_sw,
                    activo_sw,
                ], spacing=12, tight=True, scroll=ft.ScrollMode.AUTO)
            else:
                content_column = ft.Column([
                    ft.Row([nombre_field, codigo_field], spacing=15),
                    cat_dropdown,
                    ft.Row([stock_min_field, unidad_field], spacing=15),
                    ft.Divider(height=20, color="#E0E0E0"),
                    es_pesable_sw,
                    activo_sw,
                ], spacing=15, tight=True)

            # ✅ CORREGIDO: Sin fullscreen
            self.active_dialog = ft.AlertDialog(
                title=ft.Row([
                    ft.Icon(ft.Icons.INVENTORY_2, color="#388E3C", size=24 if is_mobile else 28),
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
                        bgcolor="#388E3C", 
                        color=ft.Colors.WHITE,
                    ),
                ],
                actions_alignment=ft.MainAxisAlignment.END,
                # ✅ fullscreen ELIMINADO
            )
            
            self._add_to_overlay(self.active_dialog)
            self.active_dialog.open = True
            self.page.update()
        finally:
            db.close()

    def _save_categoria(self, nombre, descripcion, color, activo, cat_id):
        db = next(get_db())
        try:
            if cat_id:
                cat = db.query(Categoria).get(cat_id)
                if cat:
                    cat.nombre = nombre
                    cat.descripcion = descripcion
                    cat.color = color
                    cat.activo = activo
            else:
                cat = Categoria(nombre=nombre, descripcion=descripcion, color=color, activo=activo)
                db.add(cat)
            db.commit()
            self._load_data()
            self._show_message("✅ Categoría guardada correctamente")
        except Exception as e:
            db.rollback()
            self._show_error(f"Error DB: {str(e)}")
        finally:
            db.close()

    def _save_producto(self, n, c, d, cat_id, rf, pu, u, sm, a, p_id, es_p=False):
        db = next(get_db())
        try:
            if p_id:
                p = db.query(Producto).get(p_id)
                if p:
                    p.nombre = n
                    p.codigo = c
                    p.descripcion = d
                    p.categoria_id = cat_id
                    p.requiere_foto_peso = rf
                    p.peso_unitario = pu
                    p.unidad_medida = u
                    p.stock_minimo = sm
                    p.activo = a
                    if hasattr(p, 'es_pesable'):
                        p.es_pesable = es_p
            else:
                p = Producto(
                    nombre=n, 
                    codigo=c, 
                    descripcion=d, 
                    categoria_id=cat_id, 
                    requiere_foto_peso=rf, 
                    peso_unitario=pu, 
                    unidad_medida=u, 
                    stock_minimo=sm, 
                    stock_actual=0, 
                    activo=a
                )
                if hasattr(p, 'es_pesable'):
                    p.es_pesable = es_p
                db.add(p)
            db.commit()
            self._load_data()
            self._show_message("✅ Producto guardado correctamente")
        except Exception as e:
            db.rollback()
            self._show_error(f"Error DB: {str(e)}")
        finally:
            db.close()

    def _confirm_delete(self, objeto, tipo="producto"):
        color = "#f44336" if tipo == "producto" else "#ff9800"
        
        self.active_dialog = ft.AlertDialog(
            title=ft.Row([
                ft.Icon(ft.Icons.WARNING, color="#f44336"),
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
                    color="#757575",
                    italic=True,
                ),
            ], spacing=10),
            actions=[
                ft.TextButton("Cancelar", on_click=self._close_dialog),
                ft.ElevatedButton(
                    "Eliminar", 
                    color=ft.Colors.WHITE,
                    bgcolor=color,
                    on_click=lambda _: self._delete_logic(objeto, tipo),
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        
        self._add_to_overlay(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _delete_logic(self, objeto, tipo):
        db = next(get_db())
        try:
            if tipo == "producto":
                item = db.query(Producto).get(objeto.id)
            else:
                item = db.query(Categoria).get(objeto.id)
            
            if item:
                item.activo = False
                db.commit()
                self._show_message(f"✅ {tipo.capitalize()} desactivado correctamente")
                self._load_data()
            self._close_dialog()
        except Exception as e:
            self._show_error(f"Error: {str(e)}")
        finally:
            db.close()

    def _load_data(self):
        db = next(get_db())
        try:
            # ✅ Detectar modo móvil ANTES de cargar datos
            self.is_mobile = self.page.width < 768 if self.page else False
            
            cats = db.query(Categoria).filter(Categoria.activo == True).all()
            prods = db.query(Producto).filter(Producto.activo == True).options(
                joinedload(Producto.categoria)
            ).all()
            
            # ✅ Usar el método correcto según el dispositivo
            if self.is_mobile:
                print(f"📱 Modo MÓVIL activado (ancho: {self.page.width}px)")  # Debug
                self.lista_categorias.controls = [self._create_categoria_item_mobile(c) for c in cats]
            else:
                print(f"💻 Modo ESCRITORIO activado (ancho: {self.page.width}px)")  # Debug
                self.lista_categorias.controls = self._create_categoria_grid(cats)
            
            self.lista_productos.controls = [self._create_producto_item(p) for p in prods]
            
            self.update()
        except Exception as e:
            print(f"Error carga: {e}")
            self._show_error(f"Error al cargar datos: {str(e)}")
        finally:
            db.close()

    def _create_categoria_grid(self, categorias):
        """Grid de 2 columnas solo para desktop"""
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
        return ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(
                        content=ft.Icon(ft.Icons.CATEGORY, color=ft.Colors.WHITE, size=28),
                        bgcolor=c.color,
                        padding=12,
                        border_radius=12,
                    ),
                    ft.Column([
                        ft.Text(c.nombre, weight=ft.FontWeight.BOLD, size=15, color="#212121"),
                        ft.Text(
                            c.descripcion or "Sin descripción", 
                            size=12, 
                            color="#757575", 
                            max_lines=1, 
                            overflow=ft.TextOverflow.ELLIPSIS,
                        ),
                    ], expand=True, spacing=2),
                ], alignment=ft.MainAxisAlignment.START),
                ft.Divider(height=1, color="#E0E0E0"),
                ft.Row([
                    ft.Container(
                        content=ft.Row([
                            ft.Icon(ft.Icons.CIRCLE, size=8, color="#388E3C" if c.activo else "#9E9E9E"),
                            ft.Text("Activo" if c.activo else "Inactivo", size=11, color="#757575"),
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
            bgcolor=ft.Colors.WHITE,
            border_radius=15,
            border=ft.border.all(1, "#E0E0E0"),
            expand=True,  # ✅ Solo en desktop
        )

    def _create_categoria_item_mobile(self, c):
        """Item de categoría para móvil - 1 sola columna"""
        return ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(
                        content=ft.Icon(ft.Icons.CATEGORY, color=ft.Colors.WHITE, size=24),
                        bgcolor=c.color,
                        padding=10,
                        border_radius=10,
                    ),
                    ft.Column([
                        ft.Text(c.nombre, weight=ft.FontWeight.BOLD, size=14, color="#212121"),
                        ft.Text(
                            c.descripcion or "Sin descripción", 
                            size=11, 
                            color="#757575", 
                            max_lines=1, 
                            overflow=ft.TextOverflow.ELLIPSIS,
                        ),
                    ], expand=True, spacing=1),
                ], alignment=ft.MainAxisAlignment.START),
                ft.Row([
                    ft.Container(
                        content=ft.Row([
                            ft.Icon(ft.Icons.CIRCLE, size=6, color="#388E3C" if c.activo else "#9E9E9E"),
                            ft.Text("Activo" if c.activo else "Inactivo", size=10, color="#757575"),
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
            bgcolor=ft.Colors.WHITE,
            border_radius=12,
            border=ft.border.all(1, "#E0E0E0"),
            # ✅ NO usar expand=True en móvil para evitar deformaciones
            width=None,  
        )

    def _create_producto_item(self, p):
        tag = ft.Container(
            content=ft.Text("PESABLE", size=9, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE),
            bgcolor="#F57C00",
            padding=ft.padding.symmetric(horizontal=6, vertical=2),
            border_radius=4,
        ) if getattr(p, 'es_pesable', False) else None

        return ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Container(
                        content=ft.Icon(ft.Icons.INVENTORY_2, color=ft.Colors.WHITE, size=24),
                        bgcolor="#1976D2",
                        padding=10,
                        border_radius=10,
                    ),
                    ft.Column([
                        ft.Row([
                            ft.Text(p.nombre, weight=ft.FontWeight.BOLD, size=14, color="#212121"),
                            tag if tag else ft.Container(),
                        ], spacing=8),
                        ft.Text(
                            f"Cat: {p.categoria.nombre if p.categoria else 'N/A'} • SKU: {p.codigo}",
                            size=11, 
                            color="#757575",
                        ),
                    ], expand=True, spacing=2),
                ], alignment=ft.MainAxisAlignment.START),
                ft.Row([
                    ft.Row([
                        ft.Icon(ft.Icons.LIST, size=14, color="#757575"),
                        ft.Text(f"Mín: {p.stock_minimo} {p.unidad_medida}", size=11, color="#757575"),
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
            bgcolor=ft.Colors.WHITE,
            border_radius=12,
            border=ft.border.all(1, "#E0E0E0"),
        )

    def _close_dialog(self, e=None):
            if self.active_dialog:
                try:
                    # Paso 1: Cerrar visualmente el diálogo
                    self.active_dialog.open = False
                    self.page.update()
                    
                    # Paso 2: Eliminar del overlay
                    if self.active_dialog in self.page.overlay:
                        self.page.overlay.remove(self.active_dialog)
                    
                    # Paso 3: Limpiar referencia
                    self.active_dialog = None
                    
                    # Paso 4: Actualizar página para limpiar residuos visuales
                    self.page.update()
                except Exception as ex:
                    print(f"Error al cerrar diálogo: {ex}")
                    self.active_dialog = None
                    self.page.update()    

    def _add_to_overlay(self, control):
        if self.page and control not in self.page.overlay:
            self.page.overlay.append(control)

    def _remove_from_overlay(self, control):
        if self.page and control in self.page.overlay:
            self.page.overlay.remove(control)

    def _show_error(self, m):
        self._remove_snackbar()
        self.active_snackbar = ft.SnackBar(
            content=ft.Row([
                ft.Icon(ft.Icons.ERROR, color=ft.Colors.WHITE),
                ft.Text(m, color=ft.Colors.WHITE),
            ], spacing=10),
            bgcolor="#d32f2f",
            margin=20,
        )
        self._add_to_overlay(self.active_snackbar)
        self.active_snackbar.open = True
        self.page.update()

    def _show_message(self, m):
        self._remove_snackbar()
        self.active_snackbar = ft.SnackBar(
            content=ft.Row([
                ft.Icon(ft.Icons.CHECK_CIRCLE, color=ft.Colors.WHITE),
                ft.Text(m, color=ft.Colors.WHITE),
            ], spacing=10),
            bgcolor="#388E3C",
            margin=20,
        )
        self._add_to_overlay(self.active_snackbar)
        self.active_snackbar.open = True
        self.page.update()

    def _remove_snackbar(self):
        if self.active_snackbar and self.page and self.active_snackbar in self.page.overlay:
            self.page.overlay.remove(self.active_snackbar)

    def _build_sistema_tab(self):
        return ft.Container(
            content=ft.Column([
                ft.Container(height=20),
                ft.Card(
                    content=ft.Container(
                        content=ft.Column([
                            ft.Row([
                                ft.Container(
                                    content=ft.Icon(ft.Icons.DASHBOARD, color=ft.Colors.WHITE, size=28),
                                    bgcolor="#7B1FA2",
                                    padding=12,
                                    border_radius=12,
                                ),
                                ft.Column([
                                    ft.Text("Mantenimiento del Sistema", weight=ft.FontWeight.BOLD, size=16),
                                    ft.Text("Herramientas de diagnóstico y configuración", size=12, color="#757575"),
                                ], spacing=2),
                            ], spacing=15),
                            ft.Divider(height=20, color="#E0E0E0"),
                            ft.Text(
                                "Si experimenta errores tras actualizaciones o cambios de configuración, use 'Probar Conexión' para verificar la base de datos.",
                                size=13,
                                color="#424242",
                            ),
                            ft.Container(height=10),
                            ft.ElevatedButton(
                                "Probar Conexión", 
                                on_click=self._test_connection_action,
                                icon=ft.Icons.STORAGE,  # ✅ CAMBIO: DATABASE → STORAGE
                                bgcolor="#7B1FA2",
                                color=ft.Colors.WHITE,
                            ),
                            ft.Container(
                                content=self.test_result_text,
                                padding=10,
                                bgcolor="#f5f5f5",
                                border_radius=8,
                                visible=False,
                            ),
                        ], spacing=15),
                        padding=25,
                    ),
                ),
            ], spacing=10, scroll=ft.ScrollMode.AUTO, expand=True),
            padding=20,
            expand=True,
        )

    def _test_connection_action(self, e):
        db = None
        try:
            db = next(get_db())
            db.execute(text("SELECT 1"))
            self.test_result_text.value = "✅ Conexión exitosa - Base de datos operativa"
            self.test_result_text.color = "#2E7D32"
            self.test_result_text.visible = True
            self._show_message("✅ Conexión a base de datos verificada")
        except Exception as ex:
            self.test_result_text.value = f"❌ Error: {str(ex)}"
            self.test_result_text.color = "#c62828"
            self.test_result_text.visible = True
            self._show_error(f"Error de conexión: {str(ex)}")
        finally:
            if db:
                db.close()
            self.update()

    def refresh(self):
        self.is_mobile = self.page.width < 768 if self.page else False
        self._load_data()