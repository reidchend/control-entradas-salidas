import flet as ft
from app.database.base import get_db
from app.models import Categoria, Producto
import os
import shutil

class ConfiguracionView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.padding = ft.padding.only(left=16, right=16, bottom=16, top=8)
        self.bgcolor = ft.colors.GREY_50
        
        # Directorio de imágenes
        self.imagenes_dir = os.path.join(os.getcwd(), "uploads", "categorias")
        os.makedirs(self.imagenes_dir, exist_ok=True)
        
        # Estado de carga de imagen y FilePicker
        self.selected_image_path = None
        self.file_picker = ft.FilePicker(on_result=self._on_file_result)
        
        # Componentes UI
        self.lista_categorias = ft.ListView(expand=True, spacing=10)
        self.lista_productos = ft.ListView(expand=True, spacing=10)
        self.tabs = None
        
        self._build_ui()

    def did_mount(self):
        # Registrar el file picker en la página al montar para que funcione
        if self.page:
            if self.file_picker not in self.page.overlay:
                self.page.overlay.append(self.file_picker)
            self.page.update()
        self._load_data()

    def _on_file_result(self, e: ft.FilePickerResultEvent):
        if e.files:
            self.selected_image_path = e.files[0].path
            if hasattr(self, "img_preview"):
                self.img_preview.value = f"Imagen seleccionada: {e.files[0].name}"
                self.img_preview.color = ft.colors.GREEN_700
                self.img_preview.update()

    def _build_ui(self):
        header = ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Text("Configuración", size=24, weight=ft.FontWeight.BOLD, color=ft.colors.BLUE_GREY_900),
                    ft.Text("Gestione sus categorías y catálogo de productos", size=14, color=ft.colors.BLUE_GREY_400),
                ], expand=True, spacing=0),
            ]),
            margin=ft.margin.only(bottom=10)
        )

        self.tabs = ft.Tabs(
            selected_index=0,
            animation_duration=300,
            tabs=[
                ft.Tab(text="Categorías", icon=ft.icons.CATEGORY_ROUNDED, content=self._build_categorias_tab()),
                ft.Tab(text="Productos", icon=ft.icons.INVENTORY_ROUNDED, content=self._build_productos_tab()),
            ],
            expand=True,
        )

        self.content = ft.Column([header, self.tabs], expand=True)

    # --- SECCIÓN CATEGORÍAS ---

    def _build_categorias_tab(self):
        return ft.Column([
            ft.Container(height=10),
            ft.ElevatedButton(
                "Nueva Categoría",
                icon=ft.icons.ADD_ROUNDED,
                style=ft.ButtonStyle(color=ft.colors.WHITE, bgcolor=ft.colors.PRIMARY),
                on_click=lambda _: self._show_categoria_dialog()
            ),
            ft.Container(height=10),
            self.lista_categorias
        ], expand=True)

    def _show_categoria_dialog(self, categoria=None):
        self.selected_image_path = None
        nombre_field = ft.TextField(
            label="Nombre de Categoría", 
            value=categoria.nombre if categoria else "",
            border_radius=10,
            focused_border_color=ft.colors.PRIMARY
        )
        
        self.img_preview = ft.Text(
            "No se ha seleccionado imagen" if not categoria else "Tiene imagen asignada (click para cambiar)",
            size=12, color=ft.colors.BLUE_GREY_400
        )

        def save_click(e):
            if not nombre_field.value:
                nombre_field.error_text = "El nombre es obligatorio"
                nombre_field.update()
                return
            self._save_categoria(nombre_field.value, categoria.id if categoria else None)
            self.page.dialog.open = False
            self.page.update()

        self.page.dialog = ft.AlertDialog(
            title=ft.Text("Gestionar Categoría"),
            content=ft.Column([
                nombre_field,
                ft.Divider(),
                ft.Text("Imagen de Portada", weight="bold", size=14),
                self.img_preview,
                ft.OutlinedButton(
                    "Seleccionar Imagen",
                    icon=ft.icons.IMAGE_SEARCH_ROUNDED,
                    on_click=lambda _: self.file_picker.pick_files(allow_multiple=False, file_type=ft.FilePickerFileType.IMAGE)
                )
            ], tight=True, spacing=15),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Guardar", bgcolor=ft.colors.PRIMARY, color=ft.colors.WHITE, on_click=save_click)
            ]
        )
        self.page.dialog.open = True
        self.page.update()

    def _save_categoria(self, nombre, cat_id=None):
        db = next(get_db())
        try:
            if cat_id:
                cat = db.query(Categoria).filter(Categoria.id == cat_id).first()
                cat.nombre = nombre
            else:
                cat = Categoria(nombre=nombre)
                db.add(cat)
            
            db.commit()
            db.refresh(cat)

            if self.selected_image_path:
                dest_path = os.path.join(self.imagenes_dir, f"{cat.id}.png")
                shutil.copy(self.selected_image_path, dest_path)

            self._load_data()
            self._show_message(f"Categoría '{nombre}' guardada correctamente")
        except Exception as ex:
            db.rollback()
            self._show_error(f"Error al guardar categoría: {ex}")
        finally:
            db.close()

    def _create_categoria_item(self, categoria):
        return ft.Container(
            content=ft.Row([
                ft.Icon(ft.icons.CATEGORY_ROUNDED, color=ft.colors.PRIMARY),
                ft.Text(categoria.nombre, weight="bold", expand=True, color=ft.colors.BLUE_GREY_900),
                ft.IconButton(ft.icons.EDIT_ROUNDED, icon_color=ft.colors.BLUE_GREY_400, on_click=lambda _: self._show_categoria_dialog(categoria)),
                ft.IconButton(ft.icons.DELETE_OUTLINE_ROUNDED, icon_color=ft.colors.RED_400, on_click=lambda _: self._show_confirm_delete(categoria.id, "categoria"))
            ]),
            padding=12, bgcolor=ft.colors.WHITE, border_radius=12, border=ft.border.all(1, ft.colors.GREY_200)
        )

    # --- SECCIÓN PRODUCTOS ---

    def _build_productos_tab(self):
        return ft.Column([
            ft.Container(height=10),
            ft.ElevatedButton(
                "Nuevo Producto",
                icon=ft.icons.ADD_BOX_ROUNDED,
                style=ft.ButtonStyle(color=ft.colors.WHITE, bgcolor=ft.colors.PRIMARY),
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

        nombre_field = ft.TextField(label="Nombre del Producto", value=producto.nombre if producto else "", border_radius=10)
        stock_min_field = ft.TextField(label="Stock Mínimo", value=str(producto.stock_minimo) if producto else "5", keyboard_type=ft.KeyboardType.NUMBER, border_radius=10)
        unidad_field = ft.TextField(label="Unidad (Kg, Unid, etc)", value=producto.unidad_medida if producto else "Unid.", border_radius=10)
        
        cat_dropdown = ft.Dropdown(
            label="Categoría",
            options=[ft.dropdown.Option(str(c.id), c.nombre) for c in categorias],
            value=str(producto.categoria_id) if producto else str(categorias[0].id),
            border_radius=10
        )

        def save_prod_click(e):
            if not nombre_field.value:
                nombre_field.error_text = "Requerido"
                nombre_field.update()
                return
            try:
                min_val = int(stock_min_field.value)
                self._save_producto(
                    nombre_field.value, 
                    int(cat_dropdown.value), 
                    min_val, 
                    unidad_field.value,
                    producto.id if producto else None
                )
                self.page.dialog.open = False
                self.page.update()
            except ValueError:
                stock_min_field.error_text = "Número inválido"
                stock_min_field.update()

        self.page.dialog = ft.AlertDialog(
            title=ft.Text("Gestionar Producto"),
            content=ft.Column([
                nombre_field,
                cat_dropdown,
                ft.Row([stock_min_field, unidad_field], spacing=10)
            ], tight=True, spacing=15),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Guardar", bgcolor=ft.colors.PRIMARY, color=ft.colors.WHITE, on_click=save_prod_click)
            ]
        )
        self.page.dialog.open = True
        self.page.update()

    def _save_producto(self, nombre, cat_id, stock_min, unidad, prod_id=None):
        db = next(get_db())
        try:
            if prod_id:
                prod = db.query(Producto).filter(Producto.id == prod_id).first()
                prod.nombre = nombre
                prod.categoria_id = cat_id
                prod.stock_minimo = stock_min
                prod.unidad_medida = unidad
            else:
                prod = Producto(
                    nombre=nombre, 
                    categoria_id=cat_id, 
                    stock_minimo=stock_min, 
                    stock_actual=0, 
                    unidad_medida=unidad
                )
                db.add(prod)
            db.commit()
            self._load_data()
            self._show_message("Producto guardado")
        except Exception as ex:
            db.rollback()
            self._show_error(f"Error: {ex}")
        finally:
            db.close()

    def _create_producto_item(self, producto):
        return ft.Container(
            content=ft.Row([
                ft.Icon(ft.icons.INVENTORY_2_ROUNDED, color=ft.colors.PRIMARY_CONTAINER),
                ft.Column([
                    ft.Text(producto.nombre, weight="bold", size=15),
                    ft.Text(f"Categoría: {producto.categoria.nombre if producto.categoria else 'N/A'}", size=12, color=ft.colors.GREY_600)
                ], expand=True, spacing=2),
                ft.IconButton(ft.icons.EDIT_ROUNDED, on_click=lambda _: self._show_producto_dialog(producto)),
                ft.IconButton(ft.icons.DELETE_OUTLINE_ROUNDED, icon_color=ft.colors.RED_400, on_click=lambda _: self._show_confirm_delete(producto.id, "producto"))
            ]),
            padding=12, bgcolor=ft.colors.WHITE, border_radius=12, border=ft.border.all(1, ft.colors.GREY_200)
        )

    # --- UTILIDADES ---

    def _load_data(self):
        try:
            db = next(get_db())
            categorias = db.query(Categoria).all()
            productos = db.query(Producto).all()
            
            self.lista_categorias.controls = [self._create_categoria_item(c) for c in categorias]
            self.lista_productos.controls = [self._create_producto_item(p) for p in productos]
            self.update()
        except Exception as e:
            print(f"Error cargando datos: {e}")
        finally:
            db.close()

    def _show_confirm_delete(self, item_id, tipo):
        def borrar(e):
            if tipo == "categoria": self._delete_categoria(item_id)
            else: self._delete_producto(item_id)
            self.page.dialog.open = False
            self.page.update()

        self.page.dialog = ft.AlertDialog(
            title=ft.Text("Confirmar eliminación"),
            content=ft.Text(f"¿Está seguro de eliminar este/a {tipo}? Esta acción no se puede deshacer."),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda _: self._close_dialog()),
                ft.ElevatedButton("Eliminar", bgcolor=ft.colors.RED_600, color=ft.colors.WHITE, on_click=borrar)
            ]
        )
        self.page.dialog.open = True
        self.page.update()

    def _delete_categoria(self, cat_id):
        db = next(get_db())
        try:
            cat = db.query(Categoria).filter(Categoria.id == cat_id).first()
            if cat:
                db.delete(cat)
                db.commit()
                img_path = os.path.join(self.imagenes_dir, f"{cat_id}.png")
                if os.path.exists(img_path): os.remove(img_path)
                self._load_data()
                self._show_message("Categoría eliminada")
        except Exception as e:
            self._show_error("No se puede eliminar: existen productos asociados")
        finally:
            db.close()

    def _delete_producto(self, prod_id):
        db = next(get_db())
        try:
            prod = db.query(Producto).filter(Producto.id == prod_id).first()
            if prod:
                db.delete(prod)
                db.commit()
                self._load_data()
                self._show_message("Producto eliminado")
        except Exception:
            self._show_error("No se puede eliminar: tiene movimientos asociados")
        finally:
            db.close()

    def _close_dialog(self):
        self.page.dialog.open = False
        self.page.update()

    def _show_message(self, message):
        self.page.show_snack_bar(ft.SnackBar(content=ft.Text(message), bgcolor=ft.colors.GREEN_700))

    def _show_error(self, error):
        self.page.show_snack_bar(ft.SnackBar(content=ft.Text(error), bgcolor=ft.colors.RED_700))