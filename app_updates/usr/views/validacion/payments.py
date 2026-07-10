import flet as ft


def _notify_error(msg, ex=None):
    try:
        from usr.notifications import show_error_with_copy
        show_error_with_copy(msg, ex)
    except Exception:
        print(f"[ERROR] {msg}: {ex}")


class PaymentsManager:
    def __init__(self, page, theme_colors):
        self.page = page
        self.theme_colors = theme_colors

        self.monto_total = 0
        self.pagos = []
        self.faltante_ves = [0]

        try:
            self._build_ui()
        except Exception as ex:
            print(f"[ERROR] PaymentsManager.__init__: {ex}")
            import traceback; traceback.print_exc()
            _notify_error("Error inicializando pagos", ex)

    def _build_ui(self):
        self.transferencia_monto = ft.TextField(
            label="🏦 Transferencia (VES)",
            prefix_icon=ft.Icons.ACCOUNT_BALANCE,
            border_radius=10,
            hint_text="0.00",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True
        )

        self.transferencia_ref = ft.TextField(
            label="Referencia",
            prefix_icon=ft.Icons.LABEL,
            border_radius=10,
            hint_text="Nro. operación...",
            expand=True
        )

        self.efectivo_monto = ft.TextField(
            label="💵 Efectivo Bs (VES)",
            prefix_icon=ft.Icons.PAYMENTS,
            border_radius=10,
            hint_text="0.00",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True
        )

        self.divisas_tasa = ft.TextField(
            label="Tasa (VES/USD)",
            prefix_icon=ft.Icons.CURRENCY_EXCHANGE,
            border_radius=10,
            hint_text="1",
            value="50",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True,
            on_change=self._on_tasa_change
        )

        self.divisas_monto = ft.TextField(
            label="Monto en USD",
            prefix_icon=ft.Icons.CURRENCY_EXCHANGE,
            border_radius=10,
            hint_text="0.00",
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True
        )

        self.pagos_list_view = ft.ListView(spacing=5, padding=10)

        self.faltante_icon = ft.Icon(ft.Icons.HOURGLASS_EMPTY, size=24)
        self.faltante_text = ft.Text(
            "Faltante: 0 VES",
            size=14,
            weight=ft.FontWeight.BOLD,
            color=self.theme_colors.get('warning', '#FF9800')
        )

        self.resumen_container = ft.Container(
            content=ft.Row([self.faltante_icon, self.faltante_text], spacing=8),
            padding=15,
            border_radius=10,
            border=ft.border.all(1, self.theme_colors.get('border', '#333333'))
        )

        self.controls_container = ft.Container(visible=False)

        self.btn_transfer = ft.ElevatedButton("🏦 Transferencia", on_click=lambda _: self._abrir_panel("transferencia"))
        self.btn_efectivo = ft.ElevatedButton("💵 Efectivo", on_click=lambda _: self._abrir_panel("efectivo"))
        self.btn_divisas = ft.ElevatedButton("💱 Divisas", on_click=lambda _: self._abrir_panel("divisas"))

    def _on_tasa_change(self, e):
        try:
            tasa = float(e.control.value or "0")
            if tasa > 0:
                faltante = max(0, self.faltante_ves[0])
                nuevo_usd = faltante / tasa
                self.divisas_monto.value = f"{nuevo_usd:.2f}" if nuevo_usd > 0 else ""
                self.page.update()
            else:
                self.divisas_monto.value = ""
                self.page.update()
        except Exception as ex:
            print(f"[ERROR] PaymentsManager._on_tasa_change: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error calculando tasa de cambio", ex)
            except:
                pass

    def _abrir_panel(self, metodo):
        try:
            self.controls_container.visible = True

            faltante = max(0, self.faltante_ves[0])
            controles = []

            if metodo == "transferencia":
                self.transferencia_monto.value = f"{int(faltante)}" if faltante > 0 else ""
                self.transferencia_ref.value = ""
                controles = [self.transferencia_monto, self.transferencia_ref]
            elif metodo == "efectivo":
                self.efectivo_monto.value = f"{int(faltante)}" if faltante > 0 else ""
                controles = [self.efectivo_monto]
            else:
                try:
                    tasa = float(self.divisas_tasa.value or "50")
                except ValueError:
                    tasa = 50
                monto_usd = faltante / tasa if tasa > 0 else 0
                self.divisas_monto.value = f"{monto_usd:.2f}" if monto_usd > 0 else ""
                controles = [self.divisas_tasa, self.divisas_monto]

            self.controls_container.content = ft.Column(
                controles + [ft.ElevatedButton("➕ Agregar", on_click=lambda _: self._agregar_pago(metodo))],
                spacing=10
            )
            self.controls_container.visible = True
            self.page.update()
        except Exception as ex:
            print(f"[ERROR] PaymentsManager._abrir_panel: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al abrir panel de pago", ex)
            except:
                pass

    def set_page(self, page):
        try:
            self.page = page
        except Exception as ex:
            print(f"[ERROR] PaymentsManager.set_page: {ex}")

    def _agregar_pago(self, metodo):
        try:
            monto = 0
            ref = ""

            if metodo == "transferencia":
                try:
                    monto = float(self.transferencia_monto.value or "0")
                except ValueError:
                    print(f"[WARN] Transferencia monto inválido")
                    monto = 0
                ref = self.transferencia_ref.value or ""
                self.transferencia_monto.value = ""
                self.transferencia_ref.value = ""

            elif metodo == "efectivo":
                try:
                    monto = float(self.efectivo_monto.value or "0")
                except ValueError:
                    print(f"[WARN] Efectivo monto inválido")
                    monto = 0
                self.efectivo_monto.value = ""

            else:
                try:
                    tasa = float(self.divisas_tasa.value or "1")
                    monto_usd = float(self.divisas_monto.value or "0")
                    monto = monto_usd * tasa
                except ValueError:
                    print(f"[WARN] Divisas monto/tasa inválido")
                    monto = 0
                self.divisas_monto.value = ""

            if monto > 0:
                self.pagos.append({
                    "tipo": metodo,
                    "monto": monto,
                    "ref": ref
                })
                self.faltante_ves[0] -= monto
                self._actualizar_lista()
                self._actualizar_resumen()
            else:
                try:
                    from usr.notifications import show_warning
                    show_warning("Ingrese un monto mayor a cero")
                except:
                    pass

            self.controls_container.visible = False
            self.page.update()
        except Exception as ex:
            print(f"[ERROR] PaymentsManager._agregar_pago: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al agregar pago", ex)
            except:
                pass

    def _actualizar_lista(self):
        try:
            self.pagos_list_view.controls.clear()
            icon_map = {"transferencia": "🏦", "efectivo": "💵", "divisas": "💱"}

            for i, pago in enumerate(self.pagos):
                texto = f"{icon_map.get(pago['tipo'], '💳')} {pago['tipo'].title()} {pago['monto']:,.0f} VES"
                if pago.get('ref'):
                    texto += f" (Ref: {pago['ref']})"

                item = ft.Container(
                    content=ft.Row([
                        ft.Text(texto, size=13, expand=True),
                        ft.IconButton(
                            icon=ft.Icons.DELETE_OUTLINE,
                            icon_color=self.theme_colors.get('error'),
                            on_click=lambda _, idx=i: self._eliminar_pago(idx)
                        )
                    ]),
                    bgcolor=self.theme_colors.get('surface'),
                    border_radius=8,
                    padding=10
                )
                self.pagos_list_view.controls.append(item)
        except Exception as ex:
            print(f"[ERROR] PaymentsManager._actualizar_lista: {ex}")

    def _eliminar_pago(self, index):
        try:
            pago = self.pagos.pop(index)
            self.faltante_ves[0] += pago['monto']
            self._actualizar_lista()
            self._actualizar_resumen()
            self.page.update()
        except Exception as ex:
            print(f"[ERROR] PaymentsManager._eliminar_pago: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al eliminar pago", ex)
            except:
                pass

    def _actualizar_resumen(self):
        try:
            faltante = self.faltante_ves[0]

            if abs(faltante) < 0.01:
                self.faltante_icon.name = ft.Icons.CHECK_CIRCLE
                self.faltante_icon.color = ft.Colors.GREEN_400
                self.faltante_text.value = "✅ PAGO COMPLETO"
            elif faltante > 0:
                self.faltante_icon.name = ft.Icons.WARNING_AMBER_ROUNDED
                self.faltante_icon.color = ft.Colors.ORANGE_400
                self.faltante_text.value = f"⚠️ FALTANTE: {faltante:,.2f} VES"
            else:
                self.faltante_icon.name = ft.Icons.ERROR_OUTLINE
                self.faltante_icon.color = ft.Colors.RED_400
                self.faltante_text.value = f"❌ EXCEDENTE: {abs(faltante):,.2f} VES"

            if self.page:
                self.page.update()
        except Exception as ex:
            print(f"[ERROR] PaymentsManager._actualizar_resumen: {ex}")

    def get_ui(self):
        return self.section_container(ft.Column([
            ft.Row([ft.Icon(ft.Icons.PAYMENTS), ft.Text("💳 Distribución de Pago", weight="bold", size=14)]),
            ft.Container(height=5),
            ft.Row([self.btn_transfer, self.btn_efectivo, self.btn_divisas], spacing=10),
            ft.Divider(height=10),
            self.controls_container,
            ft.Container(content=self.pagos_list_view, padding=10, bgcolor=self.theme_colors.get('surface'), border_radius=8),
        ], spacing=5))

    def get_resumen(self):
        return self.resumen_container

    def section_container(self, content_col):
        return ft.Container(
            content=content_col,
            padding=15,
            border_radius=12,
            border=ft.border.all(1, self.theme_colors.get('border', '#333333')),
            bgcolor=self.theme_colors.get('surface', '#252525')
        )

    def get_pagos(self):
        return self.pagos

    def set_monto_total(self, monto):
        try:
            self.monto_total = monto
            self.faltante_ves[0] = monto
            self._actualizar_resumen()
        except Exception as ex:
            print(f"[ERROR] PaymentsManager.set_monto_total: {ex}")
            try:
                from usr.notifications import show_error_with_copy
                show_error_with_copy("Error al establecer monto total", ex)
            except:
                pass