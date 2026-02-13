import flet as ft
def main(page: ft.Page):
    page.add(ft.Text("PRUEBA DE CONEXIÓN", size=40))
    page.update()
ft.app(target=main)