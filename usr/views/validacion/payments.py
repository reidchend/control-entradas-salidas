import flet as ft


class PaymentsManager:
    def __init__(self, theme_colors):
        self.theme_colors = theme_colors
        
        self.monto_total = 0
        self.pagos = []
        self.faltante_ves = [0]
        
        self._build_ui()
    
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
            keyboard_type=ft.KeyboardType.NUMBER,
            expand=True
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
    
    def _abrir_panel(self, metodo):
        self.controls_container.visible = True
        
        controles = []
        if metodo == "transferencia":
            controles = [self.transferencia_monto, self.transferencia_ref]
        elif metodo == "efectivo":
            controles = [self.efectivo_monto]
        else:
            controles = [self.divisas_tasa, self.divisas_monto]
        
        self.controls_container.content = ft.Column(
            controles + [ft.ElevatedButton("➕ Agregar", on_click=lambda _: self._agregar_pago(metodo))],
            spacing=10
        )
        self.controls_container.visible = True
        self.page.update()
    
    def set_page(self, page):
        self.page = page
    
    def _agregar_pago(self, metodo):
        monto = 0
        ref = ""
        
        if metodo == "transferencia":
            try:
                monto = float(self.transferencia_monto.value or "0")
            except:
                monto = 0
            ref = self.transferencia_ref.value or ""
            self.transferencia_monto.value = ""
            self.transferencia_ref.value = ""
        
        elif metodo == "efectivo":
            try:
                monto = float(self.efectivo_monto.value or "0")
            except:
                monto = 0
            self.efectivo_monto.value = ""
        
        else:
            try:
                tasa = float(self.divisas_tasa.value or "1")
                monto_usd = float(self.divisas_monto.value or "0")
                monto = monto_usd * tasa
            except:
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
        
        self.controls_container.visible = False
        self.page.update()
    
    def _actualizar_lista(self):
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
    
    def _eliminar_pago(self, index):
        pago = self.pagos.pop(index)
        self.faltante_ves[0] += pago['monto']
        self._actualizar_lista()
        self._actualizar_resumen()
        self.page.update()
    
    def _actualizar_resumen(self):
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
        self.monto_total = monto
        self.faltante_ves[0] = monto
        self._actualizar_resumen()