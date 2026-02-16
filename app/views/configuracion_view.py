import flet as ft
from app.database.base import get_db
from app.models import Categoria, Producto
from sqlalchemy.orm import joinedload
import os
import shutil

class ConfiguracionView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.padding = ft.padding.only(left=16, right=16, bottom=16, top=8)
        self.bgcolor = ft.Colors.GREY_50
        
        # Directorio de imágenes
        self.imagenes_dir = os.path.join(os.getcwd(), "uploads", "categorias")
        os.makedirs(self.imagenes_dir, exist_ok=True)
        
        # Estado y FilePicker
        self.selected_image_path = None
        self.file_picker = ft.FilePicker(on_result=self._on_file_result)
        
        # Componentes UI
        self.lista_categorias = ft.ListView(expand=True, spacing=10)
        self.lista_productos = ft.ListView(expand=True, spacing=10)
        self.test_result_text = ft.Text("", size=14)
        
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
            content=ft.Row([
                ft.Column([
                    ft.Text("Configuración", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_GREY_900),
                    ft.Text("Gestione sus categorías y catálogo de productos", size=14, color=ft.Colors.BLUE_GREY_400),
                ], expand=True, spacing=0),
            ]),
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

    # --- CATEGORÍAS ---

    def _build_categorias_tab(self):
        return ft.Column([
            ft.Container(height=10),
            ft.ElevatedButton(
                "Nueva Categoría",
                icon=ft.Icons.ADD_ROUNDED,
                on_click=lambda _: self._show_categoria_dialog()
            ),
            ft.Container(height=10),
            self.lista_categorias
        ], expand=True)

    def _show_categoria_dialog(self, categoria=None):
        self.selected_image_path = None
        
        nombre_field = ft.TextField(label="Nombre", value=categoria.nombre if categoria else "", expand=True)
        descripcion_field = ft.TextField(label="Descripción", value=categoria.descripcion if categoria else "", multiline=True, max_length=255)
        
        # Selector de Color (Valores por defecto del modelo)
        colores = ["#2196F3", "#F44336", "#4CAF50", "#FFEB3B", "#9C27B0", "#FF9800", "#795548", "#607D8B"]
        color_dropdown = ft.Dropdown(
            label="Color del Botón",
            options=[ft.dropdown.Option(c, c) for c in colores],
            value=categoria.color if categoria else "#2196F3",
            expand=True
        )
        
        activo_sw = ft.Switch(label="Categoría Activa", value=categoria.activo if categoria else True)
        
        self.img_preview = ft.Text(
            "Sin imagen nueva seleccionada" if not categoria else f"Imagen actual: {os.path.basename(categoria.imagen) if categoria.imagen else 'Ninguna'}",
            size=12, color=ft.Colors.BLUE_GREY_400
        )

        def save_click(e):
            if not nombre_field.value:
                nombre_field.error_text = "El nombre es obligatorio"
                nombre_field.update()
                return
            
            self._save_categoria(
                nombre=nombre_field.value,
                descripcion=descripcion_field.value,
                color=color_dropdown.value,
                activo=activo_sw.value,
                cat_id=categoria.id if categoria else None
            )
            self._close_dialog()

        dialog = ft.AlertDialog(
            title=ft.Text("Gestionar Categoría"),
            content=ft.Container(
                content=ft.Column([
                    nombre_field,
                    color_dropdown,
                    descripcion_field,
                    activo_sw,
                    ft.Divider(),
                    ft.Text("Imagen de Portada", weight="bold", size=14),
                    self.img_preview,
                    ft.OutlinedButton(
                        "Seleccionar Imagen",
                        icon=ft.Icons.IMAGE_SEARCH_ROUNDED,
                        on_click=lambda _: self.file_picker.pick_files(allow_multiple=False, file_type=ft.FilePickerFileType.IMAGE)
                    )
                ], tight=True, spacing=15, scroll=ft.ScrollMode.AUTO),
                width=400
            ),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Guardar", on_click=save_click)
            ]
        )
        
        self.page.overlay.append(dialog)
        dialog.open = True
        self.page.update()

    def _save_categoria(self, nombre, descripcion, color, activo, cat_id=None):
        db = next(get_db())
        try:
            if cat_id:
                cat = db.query(Categoria).filter(Categoria.id == cat_id).first()
                cat.nombre = nombre
                cat.descripcion = descripcion
                cat.color = color
                cat.activo = activo
            else:
                cat = Categoria(nombre=nombre, descripcion=descripcion, color=color, activo=activo)
                db.add(cat)
            
            db.commit()
            db.refresh(cat)

            # Manejo de imagen física y ruta en DB
            if self.selected_image_path:
                ext = os.path.splitext(self.selected_image_path)[1]
                nombre_archivo = f"cat_{cat.id}{ext}"
                dest_path = os.path.join(self.imagenes_dir, nombre_archivo)
                shutil.copy(self.selected_image_path, dest_path)
                
                # Actualizar la ruta en la base de datos
                cat.imagen = dest_path
                db.commit()

            self._load_data()
            self._show_message(f"Categoría '{nombre}' guardada")
        except Exception as ex:
            db.rollback()
            self._show_error(f"Error: {ex}")
        finally:
            db.close()

    # --- PRODUCTOS ---

    def _build_productos_tab(self):
        return ft.Column([
            ft.Container(height=10),
            ft.ElevatedButton(
                "Nuevo Producto",
                icon=ft.Icons.ADD_BOX_ROUNDED,
                on_click=lambda _: self._show_producto_dialog()
            ),
            ft.Container(height=10),
            self.lista_productos
        ], expand=True)

    def _show_producto_dialog(self, producto=None):
        db = next(get_db())
        categorias = db.query(Categoria).all()
        db.close()

        if not categorias:
            self._show_error("Debe crear al menos una categoría primero")
            return

        nombre_field = ft.TextField(label="Nombre", value=producto.nombre if producto else "", expand=True)
        codigo_field = ft.TextField(label="Código", value=producto.codigo if producto else "", expand=True)
        descripcion_field = ft.TextField(label="Descripción", value=producto.descripcion if producto else "", multiline=True, min_lines=2)
        
        stock_min_field = ft.TextField(label="Stock Mín.", value=str(producto.stock_minimo) if producto else "0", width=120)
        peso_unit_field = ft.TextField(label="Peso Unit. (kg)", value=str(producto.peso_unitario) if producto and producto.peso_unitario else "0", width=120)
        unidad_field = ft.TextField(label="Unidad", value=producto.unidad_medida if producto else "unidad", width=120)
        
        cat_dropdown = ft.Dropdown(
            label="Categoría",
            options=[ft.dropdown.Option(str(c.id), c.nombre) for c in categorias],
            value=str(producto.categoria_id) if producto else str(categorias[0].id),
            expand=True
        )
        
        requiere_foto_sw = ft.Switch(label="Requiere foto de peso", value=producto.requiere_foto_peso if producto else False)
        activo_sw = ft.Switch(label="Producto Activo", value=producto.activo if producto else True)

        def save_prod_click(e):
            if not nombre_field.value:
                nombre_field.error_text = "Requerido"
                nombre_field.update()
                return
            try:
                self._save_producto(
                    nombre=nombre_field.value,
                    codigo=codigo_field.value,
                    descripcion=descripcion_field.value,
                    cat_id=int(cat_dropdown.value),
                    requiere_foto=requiere_foto_sw.value,
                    peso_unit=float(peso_unit_field.value),
                    unidad=unidad_field.value,
                    stock_min=float(stock_min_field.value),
                    activo=activo_sw.value,
                    prod_id=producto.id if producto else None
                )
                self._close_dialog()
            except ValueError:
                self._show_error("Verifique los valores numéricos")

        dialog = ft.AlertDialog(
            title=ft.Text("Gestionar Producto"),
            content=ft.Container(
                content=ft.Column([
                    ft.Row([nombre_field, codigo_field]),
                    cat_dropdown,
                    descripcion_field,
                    ft.Row([stock_min_field, peso_unit_field, unidad_field]),
                    ft.Row([requiere_foto_sw, activo_sw], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                ], tight=True, spacing=15, scroll=ft.ScrollMode.AUTO),
                width=500
            ),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Guardar", on_click=save_prod_click)
            ]
        )
        self.page.overlay.append(dialog)
        dialog.open = True
        self.page.update()

    def _save_producto(self, nombre, codigo, descripcion, cat_id, requiere_foto, peso_unit, unidad, stock_min, activo, prod_id=None):
        db = next(get_db())
        try:
            if prod_id:
                prod = db.query(Producto).filter(Producto.id == prod_id).first()
                prod.nombre, prod.codigo, prod.descripcion = nombre, codigo, descripcion
                prod.categoria_id = cat_id
                prod.requiere_foto_peso, prod.peso_unitario = requiere_foto, peso_unit
                prod.unidad_medida, prod.stock_minimo, prod.activo = unidad, stock_min, activo
            else:
                prod = Producto(
                    nombre=nombre, codigo=codigo, descripcion=descripcion,
                    categoria_id=cat_id, requiere_foto_peso=requiere_foto,
                    peso_unitario=peso_unit, unidad_medida=unidad,
                    stock_minimo=stock_min, stock_actual=0, activo=activo
                )
                db.add(prod)
            db.commit()
            self._load_data()
            self._show_message("Producto guardado correctamente")
        except Exception as ex:
            db.rollback()
            self._show_error(f"Error al guardar: {ex}")
        finally:
            db.close()

    # --- SISTEMA ---

    def _build_sistema_tab(self):
        return ft.Column([
            ft.Container(height=20),
            ft.Card(
                content=ft.Container(
                    content=ft.Column([
                        ft.ListTile(leading=ft.Icon(ft.Icons.DASHBOARD_ROUNDED), title=ft.Text("Base de Datos")),
                        ft.ElevatedButton("Probar Conexión", on_click=self._test_connection_action),
                        self.test_result_text
                    ], spacing=10), padding=20
                )
            )
        ], scroll=ft.ScrollMode.AUTO, expand=True)

    def _test_connection_action(self, e):
        self.test_result_text.value = "⏳ Probando..."
        self.update()
        db = None
        try:
            db = next(get_db())
            from sqlalchemy import text
            db.execute(text("SELECT 1"))
            self.test_result_text.value = "✅ Conexión Exitosa"
            self.test_result_text.color = ft.Colors.GREEN_700
        except Exception as ex:
            self.test_result_text.value = f"❌ Error: {ex}"
            self.test_result_text.color = ft.Colors.RED_700
        finally:
            if db: db.close()
            self.update()

    # --- UTILIDADES ---

    def _load_data(self):
        db = None
        try:
            db = next(get_db())
            categorias = db.query(Categoria).all()
            productos = db.query(Producto).options(joinedload(Producto.categoria)).all()
            
            self.lista_categorias.controls = [self._create_categoria_item(c) for c in categorias]
            self.lista_productos.controls = [self._create_producto_item(p) for p in productos]
            
            if self.page:
                self.update()
        except Exception as e:
            print(f"Error load data: {e}")
        finally:
            if db: db.close()

    def _create_categoria_item(self, categoria):
        status_color = categoria.color if categoria.activo else ft.Colors.GREY_400
        return ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.CATEGORY_ROUNDED, color=status_color),
                ft.Column([
                    ft.Text(f"{categoria.nombre} {'(Inactiva)' if not categoria.activo else ''}", weight="bold"),
                    ft.Text(categoria.descripcion if categoria.descripcion else "Sin descripción", size=11, max_lines=1)
                ], expand=True, spacing=2),
                ft.IconButton(ft.Icons.EDIT_ROUNDED, on_click=lambda _: self._show_categoria_dialog(categoria)),
                ft.IconButton(ft.Icons.DELETE_OUTLINE_ROUNDED, icon_color=ft.Colors.RED_400, on_click=lambda _: self._show_confirm_delete(categoria.id, "categoria"))
            ]),
            padding=10, bgcolor=ft.Colors.WHITE, border_radius=10
        )

    def _create_producto_item(self, producto):
        status_color = ft.Colors.GREEN_400 if producto.activo else ft.Colors.GREY_400
        return ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.INVENTORY_2_ROUNDED, color=status_color),
                ft.Column([
                    ft.Text(f"{producto.nombre} {'(Inactivo)' if not producto.activo else ''}", weight="bold"),
                    ft.Text(f"Cód: {producto.codigo if producto.codigo else 'S/N'} | Cat: {producto.categoria.nombre if producto.categoria else 'N/A'}", size=11)
                ], expand=True, spacing=2),
                ft.IconButton(ft.Icons.EDIT_ROUNDED, on_click=lambda _: self._show_producto_dialog(producto)),
                ft.IconButton(ft.Icons.DELETE_OUTLINE_ROUNDED, icon_color=ft.Colors.RED_400, on_click=lambda _: self._show_confirm_delete(producto.id, "producto"))
            ]),
            padding=10, bgcolor=ft.Colors.WHITE, border_radius=10
        )

    def _show_confirm_delete(self, item_id, tipo):
        def borrar(e):
            if tipo == "categoria": self._delete_categoria(item_id)
            else: self._delete_producto(item_id)
            self._close_dialog()

        dialog = ft.AlertDialog(
            title=ft.Text("Confirmar"),
            content=ft.Text(f"¿Desea eliminar este {tipo}?"),
            actions=[
                ft.TextButton("No", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Sí, eliminar", bgcolor=ft.Colors.RED_600, color=ft.Colors.WHITE, on_click=borrar)
            ]
        )
        self.page.overlay.append(dialog)
        dialog.open = True
        self.page.update()

    def _delete_categoria(self, cat_id):
        db = next(get_db())
        try:
            cat = db.query(Categoria).filter(Categoria.id == cat_id).first()
            db.delete(cat)
            db.commit()
            self._load_data()
        except:
            self._show_error("No se puede eliminar: tiene productos asociados")
        finally: db.close()

    def _delete_producto(self, prod_id):
        db = next(get_db())
        try:
            prod = db.query(Producto).filter(Producto.id == prod_id).first()
            db.delete(prod)
            db.commit()
            self._load_data()
        except:
            self._show_error("No se puede eliminar: tiene movimientos registrados")
        finally: db.close()

    def _close_dialog(self):
        if not self.page: return
        for control in self.page.overlay[:]:
            if isinstance(control, ft.AlertDialog):
                control.open = False
        self.page.update()

    def _show_message(self, message):
        snack = ft.SnackBar(content=ft.Text(message), bgcolor=ft.Colors.GREEN_700)
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()

    def _show_error(self, error):
        snack = ft.SnackBar(content=ft.Text(str(error)), bgcolor=ft.Colors.RED_700)
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()