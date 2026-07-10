import flet as ft
from datetime import datetime

PREFIX_MAP = {
    "Factura": "F-",
    "Nota de Entrega": "NE-",
    "Entrada": "EV-",
}

class ValidacionFields:
    def __init__(self, page, theme_colors, payments=None):
        self.page = page
        self.theme_colors = theme_colors
        self.payments = payments
        try:
            self._build_fields()
        except Exception as ex:
            print(f"[ERROR] ValidacionFields.__init__: {ex}")
            import traceback; traceback.print_exc()
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error inicializando campos", ex)
            except:
                pass

    def _build_fields(self):
        self.factura_input = ft.TextField(
            label="Número de Factura",
            border_radius=10,
            autofocus=True,
            hint_text="Ej: FAC-2024-001",
            expand=True,
            on_change=self._on_factura_change
        )

        try:
            from usr.database.local_replica import LocalReplica
            proveedores = LocalReplica.get_proveedores(estado="Activo")
            proveedor_opts = [ft.dropdown.Option(p['nombre'], p['nombre']) for p in proveedores]
            if not any(o.key == "Varios" for o in proveedor_opts):
                proveedor_opts.insert(0, ft.dropdown.Option("Varios", "Varios (Entrada sin proveedor)"))
            proveedor_opts.append(ft.dropdown.Option("__nuevo__", "+ Agregar nuevo"))
        except Exception as ex:
            print(f"[WARN] No se pudieron cargar proveedores: {ex}")
            proveedor_opts = [
                ft.dropdown.Option("Varios", "Varios (Entrada sin proveedor)"),
                ft.dropdown.Option("__nuevo__", "+ Agregar nuevo")
            ]

        self.proveedor_dd = ft.Dropdown(
            label="Proveedor",
            options=proveedor_opts,
            value="Varios",
            border_radius=10,
            expand=True,
            on_change=self._on_proveedor_change
        )

        self.nuevo_proveedor_rif = ft.TextField(
            label="Nuevo RIF",
            prefix_icon=ft.Icons.BADGE,
            border_radius=10,
            width=150,
            visible=False,
            hint_text="J-XXXXXXXX-X"
        )

        self.nuevo_proveedor_input = ft.TextField(
            label="Nuevo Proveedor",
            border_radius=10,
            expand=True,
            visible=False,
            on_change=self._on_nuevo_proveedor_change
        )

        self.monto_total_input = ft.TextField(
            label="Monto Total (VES)",
            prefix_icon=ft.Icons.ATTACH_MONEY,
            border_radius=10,
            hint_text="1000.00",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True,
            on_change=self._on_monto_change
        )

        self.fecha_picker = ft.DatePicker(
            first_date=datetime(2020, 1, 1),
            last_date=datetime.now(),
            value=datetime.now()
        )

        self.fecha_label = ft.Text(
            f"Fecha: {datetime.now().strftime('%d/%m/%Y')}",
            size=12,
            color=self.theme_colors.get('text_secondary')
        )

        self.fecha_btn = ft.ElevatedButton(
            "📅 Fecha",
            on_click=self._on_fecha_btn_click
        )

        self.fecha_picker.on_change = self._on_fecha_change

        self.tipo_documento_segmented = ft.SegmentedButton(
            segments=[
                ft.Segment(value="Factura", label=ft.Text("Factura")),
                ft.Segment(value="Nota de Entrega", label=ft.Text("N. Entrega")),
                ft.Segment(value="Entrada", label=ft.Text("Entrada")),
            ],
            selected={"Factura"},
            on_change=self._on_tipo_documento_change,
            allow_empty_selection=False,
            allow_multiple_selection=False,
        )

        self.validar_btn = ft.ElevatedButton(
            "✓ Validar Entradas",
            bgcolor=self.theme_colors.get('success', '#4CAF50'),
            color="white",
            disabled=True,
            height=45
        )

        self.check_validar_button()

    def _on_factura_change(self, e):
        try:
            self.check_validar_button()
        except Exception as ex:
            print(f"[ERROR] ValidacionFields._on_factura_change: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al procesar factura", ex)
            except:
                pass

    def _on_proveedor_change(self, e):
        try:
            is_nuevo = self.proveedor_dd.value == "__nuevo__"
            self.nuevo_proveedor_input.visible = is_nuevo
            self.nuevo_proveedor_rif.visible = is_nuevo
            self.check_validar_button()
            self.page.update()
        except Exception as ex:
            print(f"[ERROR] ValidacionFields._on_proveedor_change: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al cambiar proveedor", ex)
            except:
                pass

    def _on_nuevo_proveedor_change(self, e):
        try:
            self.check_validar_button()
        except Exception as ex:
            print(f"[ERROR] ValidacionFields._on_nuevo_proveedor_change: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al procesar proveedor", ex)
            except:
                pass

    def _on_monto_change(self, e):
        try:
            if self.payments:
                try:
                    monto = float(e.control.value or "0")
                    self.payments.set_monto_total(monto)
                except ValueError as ve:
                    print(f"[WARN] Monto inválido en _on_monto_change: {ve}")
                    self.payments.set_monto_total(0)
            self.check_validar_button()
        except Exception as ex:
            print(f"[ERROR] ValidacionFields._on_monto_change: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al procesar monto", ex)
            except:
                pass

    def check_validar_button(self):
        try:
            has_proveedor = self.proveedor_dd.value and self.proveedor_dd.value != "__nuevo__"
            has_nuevo_prov = (self.proveedor_dd.value == "__nuevo__" and
                                self.nuevo_proveedor_input.value and self.nuevo_proveedor_input.value.strip())
            
            # El monto y la factura ya no son obligatorios para habilitar el botón (la factura se asigna por defecto si falta)
            completo = (has_proveedor or has_nuevo_prov)
            self.validar_btn.disabled = not completo
            try:
                self.validar_btn.update()
            except Exception:
                if self.page:
                    self.page.update()
        except Exception as ex:
            print(f"[ERROR] ValidacionFields.check_validar_button: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error validando botón", ex)
            except:
                pass

    def _on_fecha_btn_click(self, e):
        try:
            self.page.open(self.fecha_picker)
        except Exception as ex:
            print(f"[ERROR] ValidacionFields._on_fecha_btn_click: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al abrir selector de fecha", ex)
            except:
                pass

    def _on_fecha_change(self, e):
        try:
            self.fecha_label.value = f"Fecha: {self.fecha_picker.value.strftime('%d/%m/%Y')}"
            self.page.update()
        except Exception as ex:
            print(f"[ERROR] ValidacionFields._on_fecha_change: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al actualizar fecha", ex)
            except:
                pass

    def _on_tipo_documento_change(self, e):
        try:
            self._apply_tipo_prefix()
            self.check_validar_button()
            if self.page:
                self.page.update()
        except Exception as ex:
            print(f"[WARN] Error cambiando tipo documento: {ex}")

    def _apply_tipo_prefix(self):
        current = self.factura_input.value or ""
        raw = current
        for prefix in ["NE-", "EV-", "F-"]:
            if raw.upper().startswith(prefix):
                raw = raw[len(prefix):]
                break
        selected = self.tipo_documento_segmented.selected
        tipo = next(iter(selected)) if selected else "Factura"
        prefix = PREFIX_MAP.get(tipo, "F-")
        if raw:
            self.factura_input.value = f"{prefix}{raw}"

    def section_container(self, content_col):
        return ft.Container(
            content=content_col,
            padding=15,
            border_radius=12,
            border=ft.border.all(1, self.theme_colors.get('border', '#333333')),
            bgcolor=self.theme_colors.get('surface', '#252525')
        )

    def get_doc_section(self):
        return self.section_container(ft.Column([
            ft.Row([ft.Icon(ft.Icons.RECEIPT_LONG), ft.Text("📋 Datos del Documento", weight="bold", size=14)]),
            self.tipo_documento_segmented,
            ft.Row([self.factura_input], spacing=10),
            ft.Row([self.proveedor_dd], spacing=10),
            ft.Row([self.nuevo_proveedor_input, self.nuevo_proveedor_rif], spacing=10),
            ft.Row([self.fecha_btn, self.fecha_label], spacing=10),
        ], spacing=8))

    def get_monto_section(self):
        return self.section_container(ft.Column([
            ft.Row([ft.Icon(ft.Icons.ATTACH_MONEY), ft.Text("💰 Monto Total", weight="bold", size=14)]),
            self.monto_total_input,
        ], spacing=10))

    def get_validar_btn(self):
        return self.validar_btn

    def get_data(self):
        try:
            rif = ""
            if self.proveedor_dd.value == "__nuevo__":
                prov = self.nuevo_proveedor_input.value or "Varios"
                rif = self.nuevo_proveedor_rif.value or ""
            else:
                prov = self.proveedor_dd.value or "Varios"

            try:
                monto = float(self.monto_total_input.value) if self.monto_total_input.value else 0
            except ValueError as ve:
                print(f"[WARN] Monto inválido en get_data: {ve}")
                monto = 0

            fecha = self.fecha_picker.value if self.fecha_picker.value else datetime.now()

            factura_val = self.factura_input.value or ""
            if not factura_val.strip():
                factura_val = f"EV-{datetime.now().strftime('%Y%m%d%H%M%S')}"
            
            return {
                'proveedor': prov,
                'rif': rif,
                'factura': factura_val,
                'monto': monto,
                'fecha': fecha,
                'tipo_documento': next(iter(self.tipo_documento_segmented.selected)) if self.tipo_documento_segmented.selected else 'Factura'
            }
        except Exception as ex:
            print(f"[ERROR] ValidacionFields.get_data: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al obtener datos de validación", ex)
            except:
                pass
            return {
                'proveedor': 'Varios',
                'rif': '',
                'factura': f"EV-{datetime.now().strftime('%Y%m%d%H%M%S')}",
                'monto': 0,
                'fecha': datetime.now(),
                'tipo_documento': 'Factura'
            }