import flet as ft
import traceback
import os
import sys

def main(page: ft.Page):
    # Configuración básica de la página de error/carga
    page.theme_mode = ft.ThemeMode.LIGHT
    page.scroll = ft.ScrollMode.ADAPTIVE
    
    # 1. Feedback inmediato (Adiós pantalla negra)
    loading_container = ft.Container(
        content=ft.Column([
            ft.ProgressRing(),
            ft.Text("Iniciando Lycoris Control...", size=20, weight="bold"),
            status_log := ft.Text("Verificando entorno...", color="grey")
        ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),
        alignment=ft.alignment.center,
        expand=True
    )
    page.add(loading_container)
    page.update()

    try:
        # --- PASO 1: Probar Configuración ---
        status_log.value = "Cargando Pydantic y Config..."
        page.update()
        
        from config.config import get_settings
        settings = get_settings()
        
        # --- PASO 2: Probar Vistas ---
        status_log.value = "Cargando Módulos de Vistas..."
        page.update()
        
        from app.views import InventarioView, ValidacionView, StockView, ConfiguracionView, HistorialFacturasView
        
        # --- PASO 3: Intentar arrancar tu Clase Original ---
        status_log.value = "Iniciando Interfaz Principal..."
        page.update()
        
        # Aquí es donde ocurre la magia: si todo lo anterior cargó, 
        # limpiamos la pantalla y lanzamos tu lógica original.
        page.clean()
        
        # NOTA: Aquí deberías pegar o llamar a tu clase ControlEntradasSalidasApp
        # Por ahora, si llega aquí, pondremos un éxito:
        page.add(ft.Text("✅ ¡ÉXITO! Todos los módulos cargaron.", color="green", size=25))
        page.add(ft.Text(f"App Name: {settings.FLET_APP_NAME}"))
        
        # Si tienes tu clase lista, descomenta las siguientes líneas:
        # from main_original import ControlEntradasSalidasApp 
        # (O pega la clase aquí abajo y llámala)
        
    except Exception as e:
        # EL MOMENTO DE LA VERDAD: Aquí atrapamos el porqué de la pantalla negra
        page.clean()
        error_stack = traceback.format_exc()
        
        page.add(
            ft.Container(
                content=ft.Column([
                    ft.Icon(name="error_outline", color="red", size=60),
                    ft.Text("SE DETECTÓ UN ERROR CRÍTICO", size=24, weight="bold", color="red"),
                    ft.Divider(),
                    ft.Text("Detalle del error:", weight="bold"),
                    ft.Container(
                        content=ft.Text(f"{e}", color="red", selectable=True),
                        bgcolor="#ffeeee", padding=10, border_radius=5
                    ),
                    ft.Text("Ruta del fallo (Traceback):", weight="bold"),
                    ft.Container(
                        content=ft.Text(error_stack, size=11, font_family="monospace", selectable=True),
                        bgcolor="#f4f4f4", padding=10, border_radius=5
                    ),
                    ft.ElevatedButton("Reintentar", on_click=lambda _: page.update())
                ], spacing=15, scroll=ft.ScrollMode.ALWAYS),
                padding=20
            )
        )
    
    page.update()

# Punto de entrada directo para Android
if __name__ == "__main__":
    ft.app(target=main)