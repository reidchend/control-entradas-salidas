import flet as ft
from sqlalchemy import text
from usr.database.base import get_db_adaptive
from usr.notifications import show_success, show_error, show_warning, show_info
from usr.views.configuracion.helpers import _colors


def build_sistema_tab(view):
    colors = _colors(view.page)
    return ft.Container(
        content=ft.Column([
            ft.Container(height=20),
            ft.Card(
                content=ft.Container(
                    content=ft.Column([
                        ft.Row([
                            ft.Container(
                                content=ft.Icon(ft.Icons.DASHBOARD, color=colors['white'], size=28),
                                bgcolor=colors['accent_dark'],
                                padding=12,
                                border_radius=12,
                            ),
                            ft.Column([
                                ft.Text("Mantenimiento del Sistema", weight=ft.FontWeight.BOLD, size=16),
                                ft.Text("Herramientas de diagnostico y configuracion", size=12, color=colors['text_secondary']),
                            ], spacing=2),
                        ], spacing=15),
                        ft.Divider(height=20, color=colors['border']),
                        ft.Text(
                            "Si experimenta errores tras actualizaciones o cambios de configuracion, use 'Probar Conexion' para verificar la base de datos.",
                            size=13,
                            color="#424242",
                        ),
                        ft.ElevatedButton(
                            "Probar Conexion",
                            on_click=lambda e: test_connection_action(view, e),
                            icon=ft.Icons.STORAGE,
                            bgcolor="#7B1FA2",
                            color=colors['white'],
                        ),
                        ft.Divider(height=20, color=colors['border']),
                        ft.Text(
                            "Configuracion de Alertas",
                            weight=ft.FontWeight.BOLD,
                            size=14
                        ),
                        ft.Text(
                            "Habilite las notificaciones para recibir alertas de stock bajo y validaciones en tiempo real.",
                            size=12,
                            color=colors['text_secondary'],
                        ),
                        ft.ElevatedButton(
                            "Habilitar Notificaciones",
                            on_click=lambda e: request_notifications_action(view, e),
                            icon=ft.Icons.NOTIFICATIONS_ACTIVE,
                            bgcolor=colors['accent_dark'],
                            color=colors['white'],
                        ),
                        ft.Container(
                            content=view.test_result_text,
                            padding=10,
                            bgcolor=colors['bg'],
                            border_radius=8,
                            visible=False,
                        ),
                        ft.Divider(height=30, color=colors['border']),
                        ft.Text(
                            "Modo Offline",
                            weight=ft.FontWeight.BOLD,
                            size=14
                        ),
                        ft.Text(
                            "Active el modo offline para usar la aplicacion sin conexion a internet.",
                            size=12,
                            color=colors['text_secondary'],
                        ),
                        ft.Container(height=10),
                        ft.Row([
                            ft.Text("Estado:", size=14, color=colors['text_secondary']),
                            view.offline_status_indicator,
                        ], spacing=10),
                        ft.Container(height=10),
                        ft.ElevatedButton(
                            "Cambiar Modo",
                            on_click=lambda e: toggle_offline_mode(view, e),
                            icon=ft.Icons.WIFI_OFF,
                            bgcolor=colors['accent'],
                            color=colors['white'],
                        ),
                        ft.Divider(height=30, color=colors['border']),
                        ft.Text(
                            "Gestion de Operador",
                            weight=ft.FontWeight.BOLD,
                            size=14
                        ),
                        ft.Text(
                            "Cambie el operador registrado en este dispositivo.",
                            size=12,
                            color=colors['text_secondary'],
                        ),
                        ft.Container(height=10),
                        ft.ElevatedButton(
                            "Cambiar operador de este dispositivo",
                            on_click=lambda e: on_cambiar_operador(view, e),
                            icon=ft.Icons.PERSON_OUTLINED,
                            bgcolor=ft.Colors.ORANGE_600,
                            color=ft.Colors.WHITE,
                        ),
                    ], spacing=15),
                    padding=25,
                ),
            ),
        ], spacing=10, scroll=ft.ScrollMode.AUTO, expand=True),
        padding=20,
        expand=True,
    )


def test_connection_action(view, e):
    db = None
    try:
        db = next(get_db_adaptive())
        db.execute(text("SELECT 1"))
        view.test_result_text.value = "Conexion exitosa - Base de datos operativa"
        view.test_result_text.color = "#2E7D32"
        view.test_result_text.visible = True
        show_success("Conexion a base de datos verificada")
    except Exception as ex:
        view.test_result_text.value = f"Error: {str(ex)}"
        view.test_result_text.color = "#c62828"
        view.test_result_text.visible = True
        show_error(f"Error de conexion: {str(ex)}")
    finally:
        if db:
            db.close()
        view.update()


def toggle_offline_mode(view, e=None):
    from usr.database import base
    current = base.is_online()
    base._is_online = not current

    if current:
        view.offline_status_indicator.value = "FORZADO OFFLINE"
        view.offline_status_indicator.color = ft.Colors.RED_400
        show_warning("Modo offline forzado - Los datos se guardaran localmente")
    else:
        view.offline_status_indicator.value = "ONLINE"
        view.offline_status_indicator.color = ft.Colors.GREEN_400
        show_success("Conexion normal restaurada")

    view.update()


def on_cambiar_operador(view, e):
    from usr.database.local_replica import LocalReplica
    from usr.views.configuracion.dialogs import close_dialog

    usuario = LocalReplica.get_usuario_dispositivo()

    if usuario and usuario.get("pin_hash"):
        view.pin_verify_input = ft.TextField(
            label="PIN actual",
            password=True,
            max_length=4,
            keyboard_type=ft.KeyboardType.NUMBER
        )

        view.verify_dialog = ft.AlertDialog(
            title=ft.Text("Verificar PIN"),
            content=ft.Column([
                ft.Text("Ingrese su PIN actual para continuar"),
                view.pin_verify_input,
            ], tight=True),
            actions=[
                ft.TextButton("Cancelar", on_click=lambda e: close_dialog(view, e)),
                ft.ElevatedButton("Verificar", on_click=lambda e: on_verificar_pin_cambio(view, e), bgcolor=ft.Colors.DEEP_PURPLE_600, color=ft.Colors.WHITE),
            ]
        )
        view.page.overlay.append(view.verify_dialog)
        view.verify_dialog.open = True
        view.page.update()
    else:
        confirmar_cambio(view)


def on_verificar_pin_cambio(view, e):
    from usr.database.local_replica import LocalReplica
    if not view.pin_verify_input.value:
        return
    if LocalReplica.verificar_pin(view.pin_verify_input.value):
        confirmar_cambio(view)
    else:
        show_error("PIN incorrecto")


def confirmar_cambio(view):
    from usr.database.local_replica import LocalReplica
    from main import main as restart_main
    from usr.views.configuracion.dialogs import close_dialog

    close_dialog(view)
    LocalReplica.eliminar_usuario_dispositivo()
    show_info("Recargando...")
    view.page.run_task(restart_main, view.page)


def request_notifications_action(view, e):
    try:
        if hasattr(view.page, "overlay"):
            fcm_component = next((c for c in view.page.overlay if hasattr(c, "request_permission")), None)
            if fcm_component:
                fcm_component.request_permission()
                show_info("Solicitando permiso de notificaciones...")
            else:
                show_warning("El servicio de notificaciones no esta activo en este entorno.")
        else:
            show_error("No se pudo acceder al sistema de la aplicacion.")
    except Exception as ex:
        show_error(f"Error al activar notificaciones: {str(ex)}")
