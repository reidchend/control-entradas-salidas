import flet as ft
import asyncio
from usr.theme import get_theme, get_colors
from usr.database.local_replica import LocalReplica
from datetime import datetime


def _colors(page):
    return get_colors(page)


class ProduccionesView(ft.Container):
    def __init__(self):
        super().__init__()
        self.visible = False
        self.expand = True
        self.bgcolor = '#1A1A1A'
        self.padding = ft.padding.all(0)
        self._running = False

        colors = _colors(None)

        self.tabs = ft.Tabs(
            selected_index=0,
            animation_duration=300,
            tabs=[
                ft.Tab(text="Recetas", icon=ft.Icons.DESCRIPTION_OUTLINED),
                ft.Tab(text="Ejecutar", icon=ft.Icons.PLAY_CIRCLE_OUTLINED),
                ft.Tab(text="Historial", icon=ft.Icons.HISTORY_OUTLINED),
            ],
            on_change=self._on_tab_change,
        )

        self.recetas_container = ft.Container(expand=True, padding=ft.padding.all(0))
        self.ejecutar_container = ft.Container(expand=True, padding=ft.padding.all(20), visible=False)
        self.historial_container = ft.Container(expand=True, padding=ft.padding.all(20), visible=False)

        self._productos = []
        self._recetas = []
        self._selected_receta = None

    def did_mount(self):
        self._running = True
        self._build_ui()
        if self.page:
            self.page.run_task(self._load_data)
        self._update_connection_indicator()

    def will_unmount(self):
        self._running = False

    def on_theme_change(self):
        self._update_colors()

    def _update_colors(self):
        colors = _colors(self.page)
        self.bgcolor = colors.get('bg', '#1A1A1A')

    def _update_connection_indicator(self):
        if not hasattr(self, '_connection_indicator'):
            return
        try:
            from usr.database.base import check_connection
            is_online = check_connection()
            self._connection_indicator.icon = ft.Icons.CLOUD_DONE if is_online else ft.Icons.CLOUD_OFF
            self._connection_indicator.icon_color = '#4CAF50' if is_online else '#F44336'
            self._connection_indicator.tooltip = "Conectado" if is_online else "Sin conexión"
            if hasattr(self, 'page') and self.page:
                self.page.update()
        except:
            pass

    def _build_ui(self):
        colors = _colors(self.page)

        header = ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.FACTORY_OUTLINED, size=28, color=colors['accent']),
                ft.Text("Producciones", size=22, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                ft.Container(expand=True),
                self._connection_indicator if hasattr(self, '_connection_indicator') else ft.Container(),
            ], vertical_alignment=ft.CrossAxisAlignment.CENTER),
            padding=ft.padding.only(left=20, top=20, right=20, bottom=10),
        )

        self._build_recetas_tab(colors)
        self._build_ejecutar_tab(colors)
        self._build_historial_tab(colors)

        content = ft.Column([
            header,
            self.tabs,
            ft.Container(
                content=ft.Stack([
                    self.recetas_container,
                    self.ejecutar_container,
                    self.historial_container,
                ]),
                expand=True,
            ),
        ], expand=True, spacing=0)

        self.content = content

    def _build_recetas_tab(self, colors):
        self.recetas_list = ft.Column(spacing=8, scroll=ft.ScrollMode.ALWAYS, expand=True)

        add_btn = ft.FloatingActionButton(
            icon=ft.Icons.ADD,
            text="Nueva Receta",
            bgcolor=colors['accent'],
            on_click=lambda _: self._show_receta_dialog(),
        )

        self.recetas_container.content = ft.Stack([
            ft.Container(content=self.recetas_list, expand=True, padding=ft.padding.all(20)),
            ft.Container(content=ft.Row([ft.Container(expand=True), add_btn]), bottom=20, right=20),
        ])

    def _build_ejecutar_tab(self, colors):
        self.receta_dropdown = ft.Dropdown(
            label="Seleccionar Receta",
            hint_text="Elige una receta...",
            options=[],
            on_change=self._on_receta_change,
            expand=True,
        )
        self.cantidad_input = ft.TextField(
            label="Cantidad a Producir",
            hint_text="1",
            value="1",
            keyboard_type=ft.KeyboardType.NUMBER,
            width=200,
        )

        self.preview_container = ft.Container(
            padding=ft.padding.all(15),
            bgcolor=colors['card'],
            border_radius=10,
            border=ft.border.all(1, colors['border']),
            visible=False,
        )

        self.ejecutar_btn = ft.ElevatedButton(
            text="Ejecutar Producción",
            icon=ft.Icons.PLAY_ARROW,
            bgcolor=colors['accent'],
            color=colors['white'],
            on_click=self._ejecutar_produccion,
            disabled=True,
        )

        self.ejecutar_container.content = ft.Column([
            ft.Container(
                content=ft.Column([
                    ft.Text("Ejecutar Producción", size=18, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                    ft.Container(height=20),
                    ft.Row([
                        self.receta_dropdown,
                        self.cantidad_input,
                    ], spacing=15, wrap=True),
                    ft.Container(height=20),
                    self.preview_container,
                    ft.Container(height=20),
                    self.ejecutar_btn,
                ]),
                padding=ft.padding.all(20),
                bgcolor=colors['surface'],
                border_radius=10,
                border=ft.border.all(1, colors['border']),
            ),
        ], scroll=ft.ScrollMode.ALWAYS, expand=True)

    def _build_historial_tab(self, colors):
        self.historial_list = ft.Column(spacing=8, scroll=ft.ScrollMode.ALWAYS, expand=True)
        self.historial_container.content = ft.Container(
            content=self.historial_list,
            expand=True,
            padding=ft.padding.all(20),
        )

    def _on_tab_change(self, e):
        idx = self.tabs.selected_index
        self.recetas_container.visible = idx == 0
        self.ejecutar_container.visible = idx == 1
        self.historial_container.visible = idx == 2
        if idx == 1:
            asyncio.create_task(self._refresh_dropdowns())
        elif idx == 2:
            asyncio.create_task(self._load_historial())
        self.update()

    async def _load_data(self):
        await asyncio.to_thread(self._load_recetas)
        await asyncio.to_thread(self._load_productos)
        self._render_recetas()
        self._refresh_dropdowns_sync()
        if hasattr(self, 'page') and self.page:
            self.page.update()

    def _load_recetas(self):
        self._recetas = LocalReplica.get_recetas(activo=True) or []

    def _load_productos(self):
        self._productos = LocalReplica.get_productos() or []

    def _render_recetas(self):
        colors = _colors(self.page)
        controls = []

        for receta in self._recetas:
            tipo_text = "Simple" if receta.get('tipo') == 'simple' else "Compuesta"
            tipo_color = '#4CAF50' if receta.get('tipo') == 'simple' else '#2196F3'
            componentes = LocalReplica.get_componentes_by_receta(receta['id'])
            ing_count = sum(1 for c in componentes if c.get('tipo_componente') == 'INGREDIENTE')
            res_count = sum(1 for c in componentes if c.get('tipo_componente') == 'RESULTADO')

            card = ft.Container(
                content=ft.Column([
                    ft.Row([
                        ft.Container(
                            content=ft.Text(tipo_text, size=11, color=ft.Colors.WHITE, weight=ft.FontWeight.BOLD),
                            padding=ft.padding.only(left=8, right=8, top=3, bottom=3),
                            bgcolor=tipo_color,
                            border_radius=4,
                        ),
                        ft.Container(expand=True),
                        ft.IconButton(
                            icon=ft.Icons.EDIT_OUTLINED,
                            icon_size=18,
                            tooltip="Editar",
                            on_click=lambda _, r=receta: self._show_receta_dialog(r),
                        ),
                        ft.IconButton(
                            icon=ft.Icons.DELETE_OUTLINED,
                            icon_size=18,
                            icon_color='#F44336',
                            tooltip="Eliminar",
                            on_click=lambda _, r=receta: self._confirm_delete_receta(r),
                        ),
                    ]),
                    ft.Text(receta.get('nombre', ''), size=16, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                    ft.Row([
                        ft.Text(f"{len(componentes)} componentes", size=12, color=colors['text_secondary']),
                        ft.Container(width=15),
                        ft.Text(f"Cant: {receta.get('cantidad_producida', 1)}", size=12, color=colors['text_secondary']),
                    ], spacing=0),
                ], spacing=5),
                padding=ft.padding.all(15),
                bgcolor=colors['card'],
                border_radius=10,
                border=ft.border.all(1, colors['border']),
                ink=True,
                on_click=lambda _, r=receta: self._show_receta_dialog(r),
            )
            controls.append(card)

        if not controls:
            controls.append(
                ft.Container(
                    content=ft.Column([
                        ft.Icon(ft.Icons.DESCRIPTION_OUTLINED, size=48, color=colors['text_hint']),
                        ft.Text("No hay recetas aún", size=16, color=colors['text_hint']),
                        ft.Text("Presiona el botón + para crear una", size=13, color=colors['text_hint']),
                    ], horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=10),
                    padding=ft.padding.all(40),
                )
            )

        self.recetas_list.controls = controls
        if hasattr(self, 'page') and self.page:
            self.page.update()

    def _refresh_dropdowns_sync(self):
        options = []
        for r in self._recetas:
            label = f"{r.get('nombre')} ({'Simple' if r.get('tipo') == 'simple' else 'Compuesta'})"
            options.append(ft.dropdown.Option(key=str(r['id']), text=label))
        self.receta_dropdown.options = options

    async def _refresh_dropdowns(self):
        await asyncio.to_thread(self._load_recetas)
        self._refresh_dropdowns_sync()
        if hasattr(self, 'page') and self.page:
            self.page.update()

    def _show_receta_dialog(self, receta=None):
        colors = _colors(self.page)
        is_edit = receta is not None

        nombre_field = ft.TextField(
            label="Nombre de la Receta",
            value=receta.get('nombre', '') if receta else '',
            expand=True,
        )

        tipo_seg = ft.SegmentedButton(
            allow_empty_selection=False,
            selected={"simple"} if (receta and receta.get('tipo') == 'simple') or not receta else {"compuesta"},
            segments=[
                ft.Segment(value="simple", label=ft.Text("Simple")),
                ft.Segment(value="compuesta", label=ft.Text("Compuesta")),
            ],
            on_change=lambda e: _on_tipo_change(),
        )

        cant_prod = ft.TextField(
            label="Cantidad Base (por batch)",
            value=str(receta.get('cantidad_producida', 1)) if receta else "1",
            keyboard_type=ft.KeyboardType.NUMBER,
            width=150,
        )

        base_prod_dropdown = ft.Dropdown(
            label="Producto Base (origen)",
            hint_text="Seleccionar...",
            options=[
                ft.dropdown.Option(key=str(p['id']), text=f"{p['nombre']} ({p.get('tipo', 'N/A')})")
                for p in self._productos if p.get('activo')
            ],
            value=str(receta.get('producto_base_id')) if receta and receta.get('producto_base_id') else None,
            expand=True,
            visible=not receta or receta.get('tipo') == 'simple',
        )

        final_prod_dropdown = ft.Dropdown(
            label="Producto Final (resultado)",
            hint_text="Seleccionar...",
            options=[
                ft.dropdown.Option(key=str(p['id']), text=f"{p['nombre']} ({p.get('tipo', 'N/A')})")
                for p in self._productos if p.get('activo')
            ],
            value=str(receta.get('producto_final_id')) if receta and receta.get('producto_final_id') else None,
            expand=True,
            visible=receta and receta.get('tipo') == 'compuesta',
        )

        componentes_list = ft.Column(spacing=8)

        def _add_component_row(tipo_comp, prod_id=None, cantidad=None, unidad="unidad"):
            prod_dd = ft.Dropdown(
                options=[
                    ft.dropdown.Option(key=str(p['id']), text=f"{p['nombre']} ({p.get('tipo', 'N/A')})")
                    for p in self._productos if p.get('activo')
                ],
                value=str(prod_id) if prod_id else None,
                hint_text="Seleccionar...",
                expand=True,
                width=250,
            )
            cant_field = ft.TextField(
                value=str(cantidad) if cantidad else "1",
                keyboard_type=ft.KeyboardType.NUMBER,
                width=80,
            )
            unidad_field = ft.TextField(
                value=unidad,
                width=80,
                hint_text="unidad",
            )

            def _remove_row(e):
                componentes_list.controls.remove(row)
                componentes_list.update()

            row = ft.Row([
                prod_dd,
                cant_field,
                unidad_field,
                ft.IconButton(icon=ft.Icons.REMOVE_CIRCLE_OUTLINE, icon_color='#F44336', on_click=_remove_row),
            ], spacing=8, vertical_alignment=ft.CrossAxisAlignment.CENTER)

            row._prod_dd = prod_dd
            row._cant_field = cant_field
            row._unidad_field = unidad_field

            componentes_list.controls.append(row)
            return row

        tipo_label = ft.Text(
            "Productos resultantes (lo que se obtiene):" if ((receta and receta.get('tipo') == 'simple') or not receta)
            else "Ingredientes (lo que se consume):",
            size=14,
            weight=ft.FontWeight.BOLD,
            color=colors['text_primary'],
        )

        add_comp_btn = ft.TextButton(
            text="+ Agregar producto",
            icon=ft.Icons.ADD,
            on_click=lambda _: _add_component_row(
                'RESULTADO' if ((receta and receta.get('tipo') == 'simple') or not receta) else 'INGREDIENTE'
            ),
        )

        def _on_tipo_change():
            is_simple = "simple" in tipo_seg.selected
            base_prod_dropdown.visible = is_simple
            final_prod_dropdown.visible = not is_simple
            tipo_label.value = "Productos resultantes (lo que se obtiene):" if is_simple else "Ingredientes (lo que se consume):"
            add_comp_btn.text = "+ Agregar producto" if is_simple else "+ Agregar ingrediente"
            componentes_list.controls.clear()
            tipo_label.update()
            base_prod_dropdown.update()
            final_prod_dropdown.update()
            add_comp_btn.update()
            componentes_list.update()

        if receta:
            componentes = LocalReplica.get_componentes_by_receta(receta['id'])
            for comp in componentes:
                _add_component_row(
                    comp['tipo_componente'],
                    comp['producto_id'],
                    comp['cantidad'],
                    comp.get('unidad', 'unidad'),
                )

        form = ft.Column([
            nombre_field,
            ft.Row([tipo_seg, cant_prod], spacing=15, vertical_alignment=ft.CrossAxisAlignment.END),
            ft.Row([base_prod_dropdown, final_prod_dropdown], spacing=15),
            ft.Divider(height=1, color=colors['border']),
            tipo_label,
            ft.Container(content=componentes_list, padding=ft.padding.only(left=10)),
            ft.Row([add_comp_btn]),
        ], spacing=12, scroll=ft.ScrollMode.ALWAYS, height=500)

        def _save(e):
            nombre = nombre_field.value.strip() if nombre_field.value else ''
            if not nombre:
                nombre_field.error_text = "Requerido"
                nombre_field.update()
                return

            is_simple = "simple" in tipo_seg.selected
            tipo = "simple" if is_simple else "compuesta"
            cantidad = float(cant_prod.value or 1)

            receta_data = {
                'nombre': nombre,
                'tipo': tipo,
                'cantidad_producida': cantidad,
            }

            if is_simple:
                if not base_prod_dropdown.value:
                    base_prod_dropdown.error_text = "Selecciona el producto base"
                    base_prod_dropdown.update()
                    return
                receta_data['producto_base_id'] = int(base_prod_dropdown.value)
                receta_data['producto_final_id'] = None
            else:
                if not final_prod_dropdown.value:
                    final_prod_dropdown.error_text = "Selecciona el producto final"
                    final_prod_dropdown.update()
                    return
                receta_data['producto_final_id'] = int(final_prod_dropdown.value)
                receta_data['producto_base_id'] = None

            if is_edit:
                receta_data['id'] = receta['id']
                receta_data['activo'] = receta.get('activo', True)

            receta_id = LocalReplica.save_receta(receta_data)

            componentes = []
            for row in componentes_list.controls:
                if not hasattr(row, '_prod_dd') or not row._prod_dd.value:
                    continue
                componentes.append({
                    'producto_id': int(row._prod_dd.value),
                    'cantidad': float(row._cant_field.value or 1),
                    'unidad': row._unidad_field.value.strip() or 'unidad',
                    'tipo_componente': 'RESULTADO' if is_simple else 'INGREDIENTE',
                })

            LocalReplica.save_componentes(receta_id, componentes)

            if hasattr(self, 'page') and self.page:
                try:
                    self.page.close(dialog)
                except:
                    pass

            from usr.notifications import show_success
            show_success("Receta guardada correctamente")

            self._load_recetas()
            self._render_recetas()
            self._refresh_dropdowns_sync()

        def _cancel(e):
            if hasattr(self, 'page') and self.page:
                try:
                    self.page.close(dialog)
                except:
                    pass

        dialog = ft.AlertDialog(
            title=ft.Text(f"{'Editar' if is_edit else 'Nueva'} Receta", weight=ft.FontWeight.BOLD),
            content=form,
            actions=[
                ft.TextButton("Cancelar", on_click=_cancel),
                ft.FilledButton("Guardar", on_click=_save),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )

        if hasattr(self, 'page') and self.page:
            self.page.open(dialog)
            dialog.update()

    def _confirm_delete_receta(self, receta):
        def _confirm(e):
            if hasattr(self, 'page') and self.page:
                try:
                    self.page.close(dialog)
                except:
                    pass
            LocalReplica.delete_receta(receta['id'])
            from usr.notifications import show_success
            show_success("Receta eliminada")
            self._load_recetas()
            self._render_recetas()
            self._refresh_dropdowns_sync()

        def _cancel(e):
            if hasattr(self, 'page') and self.page:
                try:
                    self.page.close(dialog)
                except:
                    pass

        dialog = ft.AlertDialog(
            title=ft.Text("Eliminar Receta"),
            content=ft.Text(f"¿Eliminar '{receta.get('nombre')}'?"),
            actions=[
                ft.TextButton("Cancelar", on_click=_cancel),
                ft.FilledButton("Eliminar", on_click=_confirm, style=ft.ButtonStyle(bgcolor='#F44336', color=ft.Colors.WHITE)),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )

        if hasattr(self, 'page') and self.page:
            self.page.open(dialog)
            dialog.update()

    def _on_receta_change(self, e):
        if not self.receta_dropdown.value:
            self.preview_container.visible = False
            self.ejecutar_btn.disabled = True
            self.update()
            return

        receta_id = int(self.receta_dropdown.value)
        self._selected_receta = next((r for r in self._recetas if r['id'] == receta_id), None)

        if self._selected_receta:
            self._update_preview()
            self.ejecutar_btn.disabled = False
            self.update()

    def _update_preview(self):
        colors = _colors(self.page)
        receta = self._selected_receta
        if not receta:
            return

        cantidad = float(self.cantidad_input.value or 1)
        componentes = LocalReplica.get_componentes_by_receta(receta['id'])
        is_simple = receta.get('tipo') == 'simple'

        rows = []

        if is_simple:
            base_prod = next((p for p in self._productos if p['id'] == receta.get('producto_base_id')), None)
            if base_prod:
                rows.append(ft.Row([
                    ft.Icon(ft.Icons.REMOVE_CIRCLE, color='#FF9800', size=20),
                    ft.Text(f"Salida: {base_prod['nombre']}", weight=ft.FontWeight.BOLD, color=colors['text_primary'], expand=True),
                    ft.Text(f"-{cantidad} {base_prod.get('unidad_medida', 'unidad')}", color='#FF9800'),
                ], spacing=10))

            for comp in componentes:
                prod = next((p for p in self._productos if p['id'] == comp['producto_id']), None)
                if prod:
                    comp_cant = comp['cantidad'] * cantidad
                    rows.append(ft.Row([
                        ft.Icon(ft.Icons.ADD_CIRCLE, color='#4CAF50', size=20),
                        ft.Text(f"Entrada: {prod['nombre']}", color=colors['text_primary'], expand=True),
                        ft.Text(f"+{comp_cant} {comp.get('unidad', 'unidad')}", color='#4CAF50'),
                    ], spacing=10))
        else:
            for comp in componentes:
                prod = next((p for p in self._productos if p['id'] == comp['producto_id']), None)
                if prod:
                    comp_cant = comp['cantidad'] * cantidad
                    rows.append(ft.Row([
                        ft.Icon(ft.Icons.REMOVE_CIRCLE, color='#FF9800', size=20),
                        ft.Text(f"Salida: {prod['nombre']}", color=colors['text_primary'], expand=True),
                        ft.Text(f"-{comp_cant} {comp.get('unidad', 'unidad')}", color='#FF9800'),
                    ], spacing=10))

            final_prod = next((p for p in self._productos if p['id'] == receta.get('producto_final_id')), None)
            if final_prod:
                rows.append(ft.Row([
                    ft.Icon(ft.Icons.ADD_CIRCLE, color='#4CAF50', size=20),
                    ft.Text(f"Entrada: {final_prod['nombre']}", weight=ft.FontWeight.BOLD, color=colors['text_primary'], expand=True),
                    ft.Text(f"+{cantidad} {final_prod.get('unidad_medida', 'unidad')}", color='#4CAF50'),
                ], spacing=10))

        if not rows:
            rows.append(ft.Text("No hay componentes en esta receta", color=colors['text_hint']))

        self.preview_container.content = ft.Column([
            ft.Text("Vista previa de movimientos:", size=14, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
            ft.Divider(height=1, color=colors['border']),
            *rows,
        ], spacing=8)

        self.preview_container.visible = True

    def _ejecutar_produccion(self, e):
        receta = self._selected_receta
        if not receta:
            return

        cantidad = float(self.cantidad_input.value or 1)
        if cantidad <= 0:
            from usr.notifications import show_error
            show_error("La cantidad debe ser mayor a 0")
            return

        usuario = ""
        if hasattr(self, 'page') and self.page:
            usuario = self.page.session.get("username") or "Sistema"

        is_simple = receta.get('tipo') == 'simple'
        componentes = LocalReplica.get_componentes_by_receta(receta['id'])

        def _execute():
            prod_id = LocalReplica.save_produccion({
                'receta_id': receta['id'],
                'cantidad': cantidad,
                'estado': 'completado',
                'usuario': usuario,
                'observaciones': '',
                'fecha_produccion': datetime.now().isoformat(),
            })

            if is_simple:
                base_prod = LocalReplica.get_producto_by_id(receta['producto_base_id'])
                if base_prod:
                    almacen = base_prod.get('almacen_predeterminado', 'principal') or 'principal'
                    from usr.views.inventario.movements import registrar_movimiento
                    registrar_movimiento(
                        self.page,
                        base_prod,
                        'salida',
                        cantidad,
                        almacen=almacen,
                    )

                for comp in componentes:
                    comp_prod = LocalReplica.get_producto_by_id(comp['producto_id'])
                    if comp_prod:
                        almacen = comp_prod.get('almacen_predeterminado', 'principal') or 'principal'
                        comp_cant = comp['cantidad'] * cantidad
                        from usr.views.inventario.movements import registrar_movimiento
                        registrar_movimiento(
                            self.page,
                            comp_prod,
                            'entrada',
                            comp_cant,
                            almacen=almacen,
                        )
            else:
                for comp in componentes:
                    comp_prod = LocalReplica.get_producto_by_id(comp['producto_id'])
                    if comp_prod:
                        almacen = comp_prod.get('almacen_predeterminado', 'principal') or 'principal'
                        comp_cant = comp['cantidad'] * cantidad
                        from usr.views.inventario.movements import registrar_movimiento
                        registrar_movimiento(
                            self.page,
                            comp_prod,
                            'salida',
                            comp_cant,
                            almacen=almacen,
                        )

                final_prod = LocalReplica.get_producto_by_id(receta['producto_final_id'])
                if final_prod:
                    almacen = final_prod.get('almacen_predeterminado', 'principal') or 'principal'
                    from usr.views.inventario.movements import registrar_movimiento
                    registrar_movimiento(
                        self.page,
                        final_prod,
                        'entrada',
                        cantidad,
                        almacen=almacen,
                    )

            return prod_id

        try:
            prod_id = _execute()
            from usr.notifications import show_success
            show_success(f"Producción completada: {receta.get('nombre')} x{cantidad}")
            self._load_recetas()
        except Exception as ex:
            from usr.notifications import show_error
            show_error(f"Error al ejecutar producción: {str(ex)}")
            import traceback
            traceback.print_exc()

    async def _load_historial(self):
        colors = _colors(self.page)
        producciones = await asyncio.to_thread(LocalReplica.get_producciones)

        controls = []
        for p in producciones:
            detalles = LocalReplica.get_detalles_by_produccion(p['id'])
            entradas = [d for d in detalles if d.get('tipo') == 'entrada']
            salidas = [d for d in detalles if d.get('tipo') == 'salida']

            card = ft.Container(
                content=ft.Column([
                    ft.Row([
                        ft.Text(p.get('receta_nombre', '?'), size=16, weight=ft.FontWeight.BOLD, color=colors['text_primary']),
                        ft.Container(expand=True),
                        ft.Text(f"x{p.get('cantidad', 1)}", size=14, color=colors['accent'], weight=ft.FontWeight.BOLD),
                    ]),
                    ft.Text(f"{p.get('fecha_produccion', '')[:19]}", size=12, color=colors['text_secondary']),
                    ft.Text(f"Por: {p.get('usuario', 'Sistema')}", size=12, color=colors['text_secondary']),
                    ft.Row([
                        ft.Container(
                            content=ft.Column([
                                ft.Text(f"Salidas: {len(salidas)}", size=12, color='#FF9800'),
                                *[ft.Text(f"  - {d.get('producto_nombre', '?')} x{d['cantidad']}", size=11, color=colors['text_secondary'])
                                  for d in salidas[:3]],
                            ], spacing=2),
                            expand=True,
                        ),
                        ft.Container(
                            content=ft.Column([
                                ft.Text(f"Entradas: {len(entradas)}", size=12, color='#4CAF50'),
                                *[ft.Text(f"  + {d.get('producto_nombre', '?')} x{d['cantidad']}", size=11, color=colors['text_secondary'])
                                  for d in entradas[:3]],
                            ], spacing=2),
                            expand=True,
                        ),
                    ]),
                ], spacing=5),
                padding=ft.padding.all(15),
                bgcolor=colors['card'],
                border_radius=10,
                border=ft.border.all(1, colors['border']),
            )
            controls.append(card)

        if not controls:
            controls.append(
                ft.Container(
                    content=ft.Column([
                        ft.Icon(ft.Icons.HISTORY_OUTLINED, size=48, color=colors['text_hint']),
                        ft.Text("No hay producciones registradas", size=16, color=colors['text_hint']),
                    ], horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=10),
                    padding=ft.padding.all(40),
                )
            )

        self.historial_list.controls = controls
        if hasattr(self, 'page') and self.page:
            self.page.update()

    def on_sync_complete(self):
        self._load_recetas()
        self._render_recetas()
