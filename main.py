import flet as ft
import traceback

def main(page: ft.Page):
    page.theme_mode = ft.ThemeMode.LIGHT
    page.vertical_alignment = ft.MainAxisAlignment.CENTER
    page.horizontal_alignment = ft.CrossAxisAlignment.CENTER
    
    try:
        # Si llegamos aquí, Python y Flet funcionan
        page.add(
            ft.Icon(name=ft.icons.CHECK_CIRCLE, color="green", size=50),
            ft.Text("¡EL MOTOR FUNCIONA!", size=30, weight="bold"),
            ft.Text("Si ves esto, el problema está en las importaciones de tu main.py original.", 
                    text_align=ft.TextAlign.CENTER)
        )
    except Exception as e:
        # Si falla el renderizado, lo atrapamos
        page.add(ft.Text(f"Error de renderizado: {str(e)}", color="red"))
    
    page.update()

# Ejecución directa sin clases complejas para descartar problemas de instancia
if __name__ == "__main__":
    ft.app(target=main)