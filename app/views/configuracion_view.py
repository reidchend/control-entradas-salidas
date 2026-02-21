import flet as ft
from app.database.base import get_db
from app.models import Categoria, Producto, Movimiento
from sqlalchemy.orm import joinedload
from sqlalchemy import text
import os
import shutil

class ConfiguracionView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.padding = ft.padding.only(left=16, right=16, bottom=16, top=8)
        self.bgcolor = ft.Colors.GREY_50
        
        self.imagenes_dir = os.path.join(os.getcwd(), "uploads", "categorias")
        os.makedirs(self.imagenes_dir, exist_ok=True)
        
        self.selected_image_path = None
        self.file_picker = ft.FilePicker(on_result=self._on_file_result)
        
        self.lista_categorias = ft.ListView(expand=True, spacing=10)
        self.lista_productos = ft.ListView(expand=True, spacing=10)
        self.test_result_text = ft.Text("", size=14)
        self.active_dialog = None
        
        self._build_ui()

    def did_mount(self):
        if self.page:
            if self.file_picker not in self.page.overlay:
                self.page.overlay.append(self.file_picker)
            self.page.update()
        self._load_data()

    def _on_file_result(self, e: ft.FilePickerResultEvent):
        if e.files:
            self.selected_image_path = e.files[0].path
            if hasattr(self, "img_preview"):
                self.img_preview.value = f"Seleccionado: {e.files[0].name}"
                self.img_preview.color = ft.Colors.GREEN_700
                self.img_preview.update()

    def _build_ui(self):
        header = ft.Container(
            content=ft.Column([
                ft.Text("Configuración", size=28, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_GREY_900),
                ft.Text("Gestione sus categorías y catálogo", size=14, color=ft.Colors.BLUE_GREY_400),
            ], spacing=0),
            margin=ft.margin.only(bottom=10)
        )

        self.tabs = ft.Tabs(
            selected_index=0,
            animation_duration=300,
            tabs=[
                ft.Tab(text="Categorías", icon=ft.Icons.CATEGORY_ROUNDED, content=self._build_categorias_tab()),
                ft.Tab(text="Productos", icon=ft.Icons.INVENTORY_ROUNDED, content=self._build_productos_tab()),
                ft.Tab(text="Sistema", icon=ft.Icons.DASHBOARD_CUSTOMIZE_OUTLINED, content=self._build_sistema_tab()),
            ],
            expand=True,
        )

        self.content = ft.Column([header, self.tabs], expand=True)

    def _build_categorias_tab(self):
        return ft.Column([
            ft.Container(height=10),
            ft.FloatingActionButton(
                content=ft.Row([ft.Icon(ft.Icons.ADD), ft.Text("Nueva Categoría")], alignment="center", spacing=5),
                width=180,
                on_click=lambda _: self._show_categoria_dialog()
            ),
            ft.Container(height=10),
            self.lista_categorias
        ], expand=True)

    def _show_categoria_dialog(self, categoria=None):
        self.selected_image_path = None
        is_mobile = self.page.width < 600
        
        nombre_field = ft.TextField(label="Nombre", value=categoria.nombre if categoria else "", border=ft.InputBorder.OUTLINE)
        descripcion_field = ft.TextField(label="Descripción", value=categoria.descripcion if categoria else "", multiline=True, max_length=255, border=ft.InputBorder.OUTLINE)
        
        colores = ["#2196F3", "#F44336", "#4CAF50", "#FFEB3B", "#9C27B0", "#FF9800", "#795548", "#607D8B"]
        color_dropdown = ft.Dropdown(
            label="Color del Botón",
            options=[ft.dropdown.Option(c, c) for c in colores],
            value=categoria.color if categoria else "#2196F3",
            border=ft.InputBorder.OUTLINE
        )
        
        activo_sw = ft.Switch(label="Categoría Activa", value=categoria.activo if categoria else True)
        self.img_preview = ft.Text("Sin imagen seleccionada", size=12)

        def save_click(e):
            if not nombre_field.value:
                nombre_field.error_text = "Obligatorio"; nombre_field.update(); return
            self._save_categoria(nombre_field.value, descripcion_field.value, color_dropdown.value, activo_sw.value, categoria.id if categoria else None)
            self._close_dialog()

        self.active_dialog = ft.AlertDialog(
            title=ft.Text("Gestionar Categoría"),
            content=ft.Container(
                content=ft.Column([
                    nombre_field, color_dropdown, descripcion_field, activo_sw,
                    ft.Divider(), ft.Text("Imagen", weight="bold"), self.img_preview,
                    ft.ElevatedButton("Buscar Imagen", icon=ft.Icons.IMAGE, on_click=lambda _: self.file_picker.pick_files(file_type="image"))
                ], tight=True, spacing=15, scroll=ft.ScrollMode.AUTO),
                width=400 if not is_mobile else None
            ),
            actions=[
                ft.TextButton("Cancelar", on_click=self._close_dialog),
                ft.ElevatedButton("Guardar", on_click=save_click)
            ]
        )
        self.page.overlay.append(self.active_dialog)
        self.active_dialog.open = True
        self.page.update()

    def _build_productos_tab(self):
        return ft.Column([
            ft.Container(height=10),
            ft.FloatingActionButton(
                content=ft.Row([ft.Icon(ft.Icons.ADD_BOX), ft.Text("Nuevo Producto")], alignment="center", spacing=5),
                width=180,
                on_click=lambda _: self._show_producto_dialog()
            ),
            ft.Container(height=10),
            self.lista_productos
        ], expand=True)

    def _show_producto_dialog(self, producto=None):
        db = next(get_db())
        try:
            categorias = db.query(Categoria).filter(Categoria.activo == True).all()
            if not categorias:
                self._show_error("Debe crear al menos una categoría primero")
                return

            # --- LÓGICA DE AUTO-GENERACIÓN DE CÓDIGO CON CEROS ---
            nuevo_codigo = ""
            if not producto:  # Solo si es un producto nuevo
                try:
                    # Buscamos el código más alto convirtiéndolo a entero para ordenar bien
                    ultimo_prod = db.query(Producto).order_by(text("CAST(codigo AS INTEGER) DESC")).first()
                    
                    if ultimo_prod and ultimo_prod.codigo.isdigit():
                        longitud_original = len(ultimo_prod.codigo) # Detecta si es 4, 5, etc.
                        siguiente_numero = int(ultimo_prod.codigo) + 1
                        
                        # .zfill asegura que se mantengan los ceros (ej: "0001" -> "0002")
                        nuevo_codigo = str(siguiente_numero).zfill(longitud_original)
                    else:
                        # Código inicial por defecto con 4 dígitos
                        nuevo_codigo = "0001" 
                except Exception:
                    nuevo_codigo = "0001" 
            else:
                nuevo_codigo = producto.codigo
            # -----------------------------------------------------

            nombre_field = ft.TextField(label="Nombre", value=producto.nombre if producto else "", expand=True)
            
            # El campo código ahora tiene el valor auto-generado
            codigo_field = ft.TextField(
                label="Código/SKU", 
                value=nuevo_codigo, 
                expand=True,
                prefix_icon=ft.Icons.AUTO_AWESOME_OUTLINED, # Un icono para indicar que es automático
                helper_text="Sugerencia basada en el último registro" if not producto else ""
            )
            
            cat_dropdown = ft.Dropdown(
                label="Categoría",
                options=[ft.dropdown.Option(str(c.id), c.nombre) for c in categorias],
                value=str(producto.categoria_id) if producto else str(categorias[0].id),
                expand=True
            )
            
            stock_min_field = ft.TextField(label="Alerta Stock Mín.", value=str(producto.stock_minimo) if producto else "5", keyboard_type=ft.KeyboardType.NUMBER, expand=True)
            unidad_field = ft.TextField(label="Unidad (kg, un, m)", value=producto.unidad_medida if producto else "unidad", expand=True)
            
            es_pesable_sw = ft.Switch(label="Usa Balanza", value=getattr(producto, 'es_pesable', False) if producto else False)
            activo_sw = ft.Switch(label="Habilitado", value=producto.activo if producto else True)

            def save_prod_click(e):
                if not nombre_field.value:
                    nombre_field.error_text = "Campo requerido"; nombre_field.update(); return
                if not codigo_field.value:
                    codigo_field.error_text = "El código es necesario"; codigo_field.update(); return
                try:
                    self._save_producto(
                        nombre_field.value, codigo_field.value, "", 
                        int(cat_dropdown.value), False, 0.0, 
                        unidad_field.value, float(stock_min_field.value or 0), 
                        activo_sw.value, producto.id if producto else None, es_pesable_sw.value
                    )
                    self._close_dialog()
                except: self._show_error("Error al procesar datos")

            self.active_dialog = ft.AlertDialog(
                title=ft.Text("Ficha de Producto"),
                content=ft.Container(
                    content=ft.Column([
                        ft.Row([nombre_field, codigo_field]),
                        cat_dropdown,
                        ft.Row([stock_min_field, unidad_field]),
                        ft.Divider(),
                        es_pesable_sw,
                        activo_sw,
                    ], tight=True, spacing=20, scroll=ft.ScrollMode.AUTO),
                    width=500
                ),
                actions=[
                    ft.TextButton("Cancelar", on_click=self._close_dialog),
                    ft.ElevatedButton("Guardar", on_click=save_prod_click, bgcolor=ft.Colors.GREEN_800, color=ft.Colors.WHITE)
                ]
            )
            self.page.overlay.append(self.active_dialog)
            self.active_dialog.open = True
            self.page.update()
        finally: db.close()

    def _save_categoria(self, nombre, descripcion, color, activo, cat_id):
        db = next(get_db())
        try:
            if cat_id:
                cat = db.query(Categoria).get(cat_id)
                if cat: cat.nombre, cat.descripcion, cat.color, cat.activo = nombre, descripcion, color, activo
            else:
                cat = Categoria(nombre=nombre, descripcion=descripcion, color=color, activo=activo)
                db.add(cat)
            db.commit()
            if self.selected_image_path:
                db.refresh(cat)
                ext = os.path.splitext(self.selected_image_path)[1]
                dest = os.path.join(self.imagenes_dir, f"cat_{cat.id}{ext}")
                shutil.copy(self.selected_image_path, dest)
                cat.imagen = dest
                db.commit()
            self._load_data()
        except Exception as e:
            db.rollback(); self._show_error(f"Error DB: {e}")
        finally: db.close()

    def _save_producto(self, n, c, d, cat_id, rf, pu, u, sm, a, p_id, es_p=False):
        db = next(get_db())
        try:
            if p_id:
                p = db.query(Producto).get(p_id)
                if p:
                    p.nombre, p.codigo, p.descripcion, p.categoria_id = n, c, d, cat_id
                    p.requiere_foto_peso, p.peso_unitario, p.unidad_medida, p.stock_minimo, p.activo = rf, pu, u, sm, a
                    if hasattr(p, 'es_pesable'): p.es_pesable = es_p
            else:
                p = Producto(nombre=n, codigo=c, descripcion=d, categoria_id=cat_id, requiere_foto_peso=rf, 
                             peso_unitario=pu, unidad_medida=u, stock_minimo=sm, stock_actual=0, activo=a)
                if hasattr(p, 'es_pesable'): p.es_pesable = es_p
                db.add(p)
            db.commit()
            self._load_data()
        except Exception as e:
            db.rollback(); self._show_error(f"Error DB: {e}")
        finally: db.close()

    def _confirm_delete(self, objeto, tipo="producto"):
        self.active_dialog = ft.AlertDialog(
            title=ft.Text(f"Eliminar {tipo.capitalize()}"),
            content=ft.Text(f"¿Desea eliminar '{objeto.nombre}'? Esto lo desactivará del catálogo."),
            actions=[
                ft.TextButton("Cancelar", on_click=self._close_dialog),
                ft.TextButton("Eliminar", color="red", on_click=lambda _: self._delete_logic(objeto, tipo))
            ]
        )
        self.page.overlay.append(self.active_dialog)
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
                item.activo = False # Borrado lógico para integridad de datos
                db.commit()
                self._show_message(f"{tipo.capitalize()} desactivado")
                self._load_data()
            self._close_dialog()
        finally:
            db.close()

    def _load_data(self):
        db = next(get_db())
        try:
            cats = db.query(Categoria).filter(Categoria.activo == True).all()
            prods = db.query(Producto).filter(Producto.activo == True).options(joinedload(Producto.categoria)).all()
            self.lista_categorias.controls = [self._create_categoria_item(c) for c in cats]
            self.lista_productos.controls = [self._create_producto_item(p) for p in prods]
            self.update()
        except Exception as e:
            print(f"Error carga: {e}")
        finally: db.close()

    def _create_categoria_item(self, c):
        return ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.CATEGORY, color=c.color),
                ft.Column([ft.Text(c.nombre, weight="bold"), ft.Text(c.descripcion or "", size=11)], expand=True, spacing=1),
                ft.IconButton(ft.Icons.EDIT, on_click=lambda _: self._show_categoria_dialog(c)),
                ft.IconButton(ft.Icons.DELETE_OUTLINE, icon_color="red", on_click=lambda _: self._confirm_delete(c, "categoria")),
            ]),
            padding=10, bgcolor="white", border_radius=10, border=ft.border.all(1, ft.Colors.GREY_200)
        )

    def _create_producto_item(self, p):
        tag = " [PESABLE]" if getattr(p, 'es_pesable', False) else ""
        return ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.INVENTORY_2, color="blue"),
                ft.Column([
                    ft.Text(f"{p.nombre}{tag}", weight="bold"), 
                    ft.Text(f"Cat: {p.categoria.nombre if p.categoria else 'N/A'}", size=11)
                ], expand=True, spacing=1),
                ft.IconButton(ft.Icons.EDIT, on_click=lambda _: self._show_producto_dialog(p)),
                ft.IconButton(ft.Icons.DELETE_OUTLINE, icon_color="red", on_click=lambda _: self._confirm_delete(p, "producto")),
            ]),
            padding=10, bgcolor="white", border_radius=10, border=ft.border.all(1, ft.Colors.GREY_200)
        )

    def _close_dialog(self, e=None):
        if self.active_dialog:
            self.active_dialog.open = False
        self.page.update()

    def _show_error(self, m):
        s = ft.SnackBar(content=ft.Text(m), bgcolor="red")
        self.page.overlay.append(s); s.open = True; self.page.update()

    def _show_message(self, m):
        s = ft.SnackBar(content=ft.Text(m), bgcolor="green")
        self.page.overlay.append(s); s.open = True; self.page.update()

    def _build_sistema_tab(self):
        return ft.Column([
            ft.Container(height=20),
            ft.Card(content=ft.Container(content=ft.Column([
                ft.ListTile(leading=ft.Icon(ft.Icons.DASHBOARD), title=ft.Text("Mantenimiento")),
                ft.Text("Si experimenta errores tras actualizaciones, use 'Probar Conexión'."),
                ft.ElevatedButton("Probar Conexión", on_click=self._test_connection_action),
                self.test_result_text
            ], spacing=10), padding=20))
        ], scroll=ft.ScrollMode.AUTO, expand=True)

    def _test_connection_action(self, e):
        db = None
        try:
            db = next(get_db()); db.execute(text("SELECT 1"))
            self.test_result_text.value = "✅ OK"; self.test_result_text.color = "green"
        except Exception as ex:
            self.test_result_text.value = f"❌ Error: {ex}"; self.test_result_text.color = "red"
        finally:
            if db: db.close()
            self.update()