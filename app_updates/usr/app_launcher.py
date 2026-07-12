import traceback
import os
import asyncio
import sys
import flet as ft
from usr.logger import get_logger

logger = get_logger(__name__)


def get_theme_colors(page):
    is_dark = page.theme_mode == ft.ThemeMode.DARK
    return {
        'bg': '#121212' if is_dark else '#F5F5F5',
        'surface': '#1E1E1E' if is_dark else '#FFFFFF',
        'surface_container': '#2D2D2D' if is_dark else '#FAFAFA',
        'text_primary': '#FFFFFF' if is_dark else '#1A1A1A',
        'text_secondary': '#B0B0B0' if is_dark else '#666666',
        'accent': '#BB86FC' if is_dark else '#6200EE',
    }


def mostrar_error_critico(page: ft.Page, error_completo: str):
    try:
        page.clean()
        page.bgcolor = "#1a0000"

        error_container = ft.Column(
            scroll=ft.ScrollMode.ALWAYS,
            expand=True,
            controls=[
                ft.Text("DETALLES TÉCNICOS:", weight=ft.FontWeight.BOLD, color=ft.Colors.RED_200),
                ft.Container(
                    content=ft.Text(
                        error_completo,
                        size=11,
                        font_family="monospace",
                        color=ft.Colors.RED_100,
                    ),
                    padding=10,
                    bgcolor="#330000",
                    border_radius=5,
                ),
            ],
        )

        page.add(
            ft.Container(
                padding=20,
                content=ft.Column([
                    ft.Icon(ft.Icons.REPORT_PROBLEM_ROUNDED, color=ft.Colors.RED_400, size=50),
                    ft.Text("Error de Inicio", size=24, weight=ft.FontWeight.BOLD),
                    ft.Text("La aplicación no pudo arrancar correctamente.", text_align=ft.TextAlign.CENTER),
                    ft.Divider(color=ft.Colors.RED_900),
                    ft.Container(content=error_container, height=300),
                    ft.ElevatedButton(
                        "Copiar Error al Portapapeles",
                        icon=ft.Icons.COPY,
                        on_click=lambda _: page.set_clipboard(error_completo),
                    ),
                    ft.Container(height=10),
                    ft.ElevatedButton(
                        "Reintentar Inicio",
                        bgcolor=ft.Colors.RED_700,
                        color=ft.Colors.WHITE,
                        on_click=lambda _: page.go("/"),
                    ),
                ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),
            ),
        )
        page.update()
    except Exception as e:
        print(f"CRITICAL ERROR in mostrar_error_critico: {e}")


async def main(page: ft.Page):
    from main import resource_path

    # Silenciar mensajes molestos de asyncio
    loop = asyncio.get_running_loop()
    if loop.get_debug():
        loop.set_debug(False)
    _old_handler = loop.get_exception_handler()

    def _filter_asyncio_warnings(_loop, context):
        if 'Task was destroyed' in context.get('message', ''):
            return
        if _old_handler:
            _old_handler(_loop, context)
        else:
            loop.default_exception_handler(context)

    loop.set_exception_handler(_filter_asyncio_warnings)

    page.bgcolor = "#121212"
    page.theme_mode = ft.ThemeMode.DARK

    from usr.error_handler import set_page
    set_page(page)

    page.title = "Lycoris Control"
    page.favicon = "favicon.png"
    page.assets_allow_override = True

    page.window.icon = resource_path("assets/icono.ico")

    page.locale_configuration = ft.LocaleConfiguration(
        supported_locales=[ft.Locale("es")],
        current_locale=ft.Locale("es"),
    )

    import locale
    try:
        locale.setlocale(locale.LC_ALL, 'es_ES.UTF-8')
    except:
        try:
            locale.setlocale(locale.LC_ALL, 'es_MX.UTF-8')
        except:
            try:
                locale.setlocale(locale.LC_ALL, 'spanish')
            except:
                pass

    try:
        page.bgcolor = "#121212"
        page.update()

        from usr.database.conn import set_db_path, get_db_path

        db_dir = "."
        try:
            platform = getattr(page, 'platform', None)
            if platform and str(platform) in ('android', 'ios', 'android_tv'):
                if hasattr(page, 'app_data_dir') and page.app_data_dir:
                    db_dir = page.app_data_dir
        except:
            pass

        page.session.set("_db_dir", db_dir)
        db_path = os.path.abspath(os.path.join(db_dir, "lycoris_local.db"))

        from usr.database.local_replica import ensure_local_db

        try:
            set_db_path(db_path)
        except Exception as e:
            print(f"[WARN] Error set_db_path: {e}")
            try:
                set_db_path("lycoris_local.db")
            except Exception as e2:
                print(f"[WARN] Error set_db_path fallback: {e2}")

        try:
            ensure_local_db()
        except Exception as e:
            print(f"[WARN] Error ensure_local_db: {e}")

        logo = ft.Column([
            ft.Image(src="icono.png", width=120, height=120, fit=ft.ImageFit.CONTAIN, error_content=ft.Text("Logo no encontrado", color=ft.Colors.RED)),
            ft.Text("Lycoris", size=32, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE),
            ft.Text("Control de Entradas y Salidas", size=16, color="#9E9E9E"),
        ], horizontal_alignment="center", spacing=10)

        progress = ft.ProgressRing(width=60, height=60, stroke_width=5, color="#BB86FC", bgcolor="#2D2D2D")
        step_text = ft.Text("Cargando...", size=18, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE)
        status_text = ft.Text("Inicializando...", size=14, color="#9E9E9E")

        loading = ft.Container(
            content=ft.Column([logo, ft.Container(height=40), progress, ft.Container(height=20), step_text, status_text], horizontal_alignment="center", spacing=0),
            alignment=ft.alignment.center,
            expand=True,
            bgcolor="#121212",
        )

        page.add(loading)
        page.update()

        from usr.updater import comprobar_y_aplicar_actualizaciones, _get_app_dir

        try:
            await comprobar_y_aplicar_actualizaciones(page, status_text)
        except Exception as e_up:
            print(f"[LAUNCHER] Error ejecutando actualizador: {e_up}")

        updates_dir = os.path.join(_get_app_dir(), "app_updates")
        if os.path.exists(updates_dir):
            sys.path.insert(0, updates_dir)
            updates_usr = os.path.join(updates_dir, "usr")
            if os.path.exists(updates_usr):
                import usr
                usr.__path__ = [os.path.abspath(updates_usr)]
                # Forzar recarga de cualquier módulo de 'usr' ya cargado (evita caché viejo)
                for key in list(sys.modules.keys()):
                    if key == "usr" or key.startswith("usr."):
                        sys.modules.pop(key, None)
                # Re-establecer la ruta de BD en el conn recién cargado desde app_updates
                # (sys.modules.pop borró _db_path, y la nueva importación lo crea como None)
                from usr.database.conn import set_db_path as _reset_db_path
                _reset_db_path(db_path)
                # DIAGNÓSTICO: verificar el archivo físico en app_updates
                try:
                    _updates_usr_dir = os.path.join(updates_dir, "usr", "database", "local_replica.py")
                    _content = open(_updates_usr_dir, encoding='utf-8').read()
                    _has_debug = '[LOCAL_REPLICA]' in _content
                    _has_sync_debug = '[SYNC-DEBUG]' in _content
                    _size = len(_content)
                    print(f"[LAUNCHER] app_updates/local_replica.py: {_size}B, [LOCAL_REPLICA]={'SÍ' if _has_debug else 'NO'}, [SYNC-DEBUG]={'SÍ' if _has_sync_debug else 'NO'}")
                except Exception as _e_read:
                    print(f"[LAUNCHER] Error leyendo app_updates/local_replica.py: {_e_read}")
            print(f"[LAUNCHER] Cargando código actualizado desde {updates_dir}")

        await asyncio.sleep(0.5)

        step_text.value = "2/5"
        status_text.value = "Configurando..."
        page.update()
        await asyncio.sleep(0.5)

        from config.config import get_settings
        settings = get_settings()
        status_text.value = "✓ Lista"
        page.update()

        await asyncio.sleep(0.5)

        step_text.value = "3/5"
        status_text.value = "Base de datos..."
        page.update()

        from usr.database.base import get_engine, get_session, init_local_tables, check_connection
        from usr.database.local_replica import LocalReplica
        from usr.database.sync import init_sync_manager

        await asyncio.sleep(0.1)
        from usr.views.login_view import LoginView
        setup_done = asyncio.Event()

        async def after_login():
            setup_done.set()

        usuario = await asyncio.to_thread(LocalReplica.get_usuario_dispositivo)

        if usuario is None:
            page.clean()
            login_view = LoginView(modo="registro", on_success=after_login)
            page.add(login_view)
            page.update()
            await setup_done.wait()
        elif usuario.get("pin_hash"):
            page.clean()
            login_view = LoginView(modo="pin", on_success=after_login)
            page.add(login_view)
            page.update()
            await setup_done.wait()
        else:
            page.session.set("username", usuario.get("nombre", "Operador"))

        page.clean()
        page.add(loading)
        if page.session.get("username"):
            status_text.value = f"✓ Hola, {page.session.get('username')}"
        else:
            status_text.value = f"✓ Hola, {page.session.get('username', 'Usuario')}"
        page.update()
        await asyncio.sleep(0.5)

        sync_manager = init_sync_manager(get_engine)
        sync_manager.set_session_local_getter(get_session)

        is_online = check_connection()
        print(f"[MAIN] check_connection(): {is_online}")

        if is_online:
            status_text.value = "✓ Conectado"
        else:
            status_text.value = " Modo offline"

        page.update()

        await asyncio.sleep(0.5)

        step_text.value = "4/5"
        status_text.value = "Sincronizando..."
        page.update()

        if check_connection():
            try:
                await asyncio.to_thread(sync_manager.full_sync)
                status_text.value = "✓ Sincronizado"
            except Exception as e:
                print(f"Error en sync inicial: {e}")
                status_text.value = " Sin sync"
        else:
            status_text.value = " Modo offline"
        page.update()

        await asyncio.sleep(0.5)

        step_text.value = "5/5"
        status_text.value = "Modulos..."
        page.update()

        await asyncio.sleep(0.5)
        from usr.views import InventarioView, ValidacionView, StockView, ProduccionesView, ConfiguracionView, HistorialFacturasView, RequisicionesView, BandejaWhatsAppView
        status_text.value = "✓ Cargado"
        page.update()

        from usr.app_controller import ControlEntradasSalidasApp
        app_instance = ControlEntradasSalidasApp()
        status_text.value = "✓ Creado"
        page.update()

        await asyncio.sleep(0.5)

        step_text.value = "Listo!!!"
        page.update()
        await asyncio.sleep(0.5)

        status_text.value = "Iniciando..."
        page.update()
        await asyncio.sleep(0.5)

        await app_instance.arrancar_interfaz(page, settings, None)

    except Exception as inner_e:
        error_log = traceback.format_exc()
        logger.error(f"Exception in main(): {error_log}")
        db_dir = page.session.get("_db_dir") or "."
        try:
            log_path = os.path.join(db_dir, "error_log.txt")
            with open(log_path, "w") as f:
                f.write(error_log)
        except:
            pass
        mostrar_error_critico(page, error_log)
