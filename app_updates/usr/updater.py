import asyncio
import json
import os
import shutil
import ssl
import sys
import urllib.request
import zipfile

import certifi
import flet as ft


def _get_app_dir() -> str:
    """Directorio donde guardar datos mutables (.env, version.json, app_updates)."""
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _ssl_context():
    ctx = ssl.create_default_context(cafile=certifi.where())
    ctx.check_hostname = True
    ctx.verify_mode = ssl.CERT_REQUIRED
    return ctx


def _read_env(var_name: str) -> str:
    """Lee UPDATE_URL desde .env. Busca en _get_app_dir() y en sys._MEIPASS (fallback compilado)."""
    locations = [_get_app_dir()]
    if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
        locations.append(sys._MEIPASS)

    for base in locations:
        path = os.path.join(base, ".env")
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    for line in f:
                        if line.strip().startswith(f"{var_name}="):
                            return line.split("=")[1].strip().strip('"').strip("'")
            except Exception as e:
                print(f"[UPDATER] Error leyendo {path}: {e}")
    return ""


def _fetch_url(url: str, timeout: int) -> bytes:
    """Bloqueante — corre en executor."""
    ctx = _ssl_context()
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        return r.read()


def _download_file(url: str, dest: str, block_size=8192):
    """Bloqueante — corre en executor."""
    ctx = _ssl_context()
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    resp = urllib.request.urlopen(req, timeout=120, context=ctx)
    with open(dest, 'wb') as out:
        while True:
            chunk = resp.read(block_size)
            if not chunk:
                break
            out.write(chunk)


async def comprobar_y_aplicar_actualizaciones(page: ft.Page, status_text: ft.Text):
    """Comprueba, descarga e instala actualizaciones de código de forma dinámica."""

    app_dir = _get_app_dir()
    version_path = os.path.join(app_dir, "version.json")
    updates_dir = os.path.join(app_dir, "app_updates")
    zip_temp = os.path.join(app_dir, "update_temp.zip")
    temp_extract_dir = os.path.join(app_dir, "temp_extract")

    # 1. Obtener UPDATE_URL
    update_url = _read_env("UPDATE_URL")

    if not update_url:
        status_text.value = "Sin URL de actualización configurada"
        status_text.color = "#9E9E9E"
        page.update()
        await asyncio.sleep(0.5)
        return

    status_text.value = "Buscando actualizaciones..."
    page.update()
    await asyncio.sleep(0.05)  # dar chance a que se renderice

    # 2. Versión local
    local_version = "1.0.0"
    if os.path.exists(version_path):
        try:
            with open(version_path, "r", encoding="utf-8") as f:
                local_version = json.load(f).get("version", "1.0.0")
        except Exception as e:
            print(f"[UPDATER] Error leyendo version.json local: {e}")

    try:
        # 3. Consultar versión remota (en executor para no bloquear)
        raw = await asyncio.to_thread(_fetch_url, update_url, 4)
        remote_info = json.loads(raw.decode('utf-8'))

        remote_version = remote_info.get("version", "1.0.0")
        zip_url = remote_info.get("zip_url", "")

        if remote_version == local_version:
            status_text.value = f"Aplicación al día (v{local_version})"
            status_text.color = "#4CAF50"
            page.update()
            await asyncio.sleep(0.5)
            return

        if not zip_url:
            status_text.value = f"Nueva versión {remote_version} disponible, pero sin URL de descarga"
            status_text.color = "#FF9800"
            page.update()
            await asyncio.sleep(2)
            return

        # 4. Preguntar al usuario
        response_event = asyncio.Event()
        proceed = False

        def _cerrar_dialogo():
            page.close(dialog)

        def on_yes(e):
            nonlocal proceed
            proceed = True
            _cerrar_dialogo()
            response_event.set()

        def on_no(e):
            nonlocal proceed
            proceed = False
            _cerrar_dialogo()
            response_event.set()

        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Row([
                ft.Icon(ft.Icons.SYSTEM_UPDATE, color=ft.Colors.BLUE_400),
                ft.Text("Actualización disponible", weight=ft.FontWeight.BOLD),
            ], spacing=10),
            content=ft.Column([
                ft.Text(f"Versión actual: {local_version}", size=14),
                ft.Row([
                    ft.Icon(ft.Icons.ARROW_FORWARD, size=16, color=ft.Colors.GREEN_400),
                    ft.Text(f"Nueva versión: {remote_version}", weight=ft.FontWeight.BOLD, size=15),
                ], spacing=6),
                ft.Container(height=10),
                ft.Text("¿Desea descargar e instalar la actualización ahora?"),
                ft.Text(
                    "Los cambios se aplicarán al reiniciar la aplicación.",
                    size=12, color=ft.Colors.GREY_400, italic=True,
                ),
            ], tight=True, spacing=8),
            actions=[
                ft.TextButton("Más tarde", on_click=on_no),
                ft.ElevatedButton(
                    "Actualizar ahora",
                    on_click=on_yes,
                    bgcolor=ft.Colors.BLUE_600,
                    color=ft.Colors.WHITE,
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )

        page.open(dialog)

        await response_event.wait()

        if not proceed:
            status_text.value = "Actualización omitida"
            page.update()
            await asyncio.sleep(0.5)
            return

        # 5. Descargar (en executor para no bloquear el event loop)
        status_text.value = "Descargando actualización..."
        page.update()

        await asyncio.to_thread(_download_file, zip_url, zip_temp)

        # 6. Instalar
        status_text.value = "Instalando actualización..."
        page.update()

        if os.path.exists(temp_extract_dir):
            shutil.rmtree(temp_extract_dir)
        os.makedirs(temp_extract_dir)

        with zipfile.ZipFile(zip_temp, 'r') as zip_ref:
            zip_ref.extractall(temp_extract_dir)

        src_dir = temp_extract_dir
        subdirs = [os.path.join(temp_extract_dir, d) for d in os.listdir(temp_extract_dir)
                   if os.path.isdir(os.path.join(temp_extract_dir, d))]
        if len(subdirs) == 1 and not os.path.exists(os.path.join(temp_extract_dir, "usr")):
            src_dir = subdirs[0]

        src_usr = os.path.join(src_dir, "usr")
        if os.path.exists(src_usr):
            dest_usr = os.path.join(updates_dir, "usr")
            if os.path.exists(dest_usr):
                shutil.rmtree(dest_usr)
            shutil.copytree(src_usr, dest_usr)

        src_config = os.path.join(src_dir, "config")
        if os.path.exists(src_config):
            dest_config = os.path.join(updates_dir, "config")
            if os.path.exists(dest_config):
                shutil.rmtree(dest_config)
            shutil.copytree(src_config, dest_config)

        with open(version_path, "w", encoding="utf-8") as f:
            json.dump({"version": remote_version, "zip_url": zip_url}, f)

        shutil.rmtree(temp_extract_dir)
        if os.path.exists(zip_temp):
            os.remove(zip_temp)

        status_text.value = f"¡Actualización v{remote_version} lista!"
        status_text.color = "#4CAF50"
        page.update()
        await asyncio.sleep(1)

    except Exception as e:
        print(f"[UPDATER] Error: {e}")
        status_text.value = "Error al buscar actualización"
        status_text.color = "#c62828"
        page.update()
        await asyncio.sleep(1)
