import asyncio
import json
import os
import shutil
import sys
import urllib.request
import zipfile

import flet as ft


def _get_app_dir() -> str:
    """Directorio donde guardar datos mutables (.env, version.json, app_updates)."""
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


async def comprobar_y_aplicar_actualizaciones(page: ft.Page, status_text: ft.Text):
    """Comprueba, descarga e instala actualizaciones de código de forma dinámica."""

    app_dir = _get_app_dir()
    env_path = os.path.join(app_dir, ".env")
    version_path = os.path.join(app_dir, "version.json")
    updates_dir = os.path.join(app_dir, "app_updates")
    zip_temp = os.path.join(app_dir, "update_temp.zip")
    temp_extract_dir = os.path.join(app_dir, "temp_extract")

    # 1. Obtener la URL de actualización de forma aislada
    update_url = ""
    try:
        if os.path.exists(env_path):
            with open(env_path, "r", encoding="utf-8") as f:
                for line in f:
                    if line.strip().startswith("UPDATE_URL="):
                        update_url = line.split("=")[1].strip().strip('"').strip("'")
                        break
    except Exception as e:
        print(f"[UPDATER] Error leyendo .env: {e}")

    if not update_url:
        print("[LAUNCHER] UPDATE_URL no configurada en .env. Omitiendo actualizaciones.")
        return

    status_text.value = "Buscando actualizaciones..."
    page.update()

    # 2. Obtener versión local actual
    local_version = "1.0.0"
    if os.path.exists(version_path):
        try:
            with open(version_path, "r", encoding="utf-8") as f:
                local_version = json.load(f).get("version", "1.0.0")
        except Exception as e:
            print(f"[UPDATER] Error leyendo version.json local: {e}")

    try:
        # 3. Descargar metadata remota (version.json)
        req = urllib.request.Request(update_url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=4) as response:
            remote_info = json.loads(response.read().decode('utf-8'))

        remote_version = remote_info.get("version", "1.0.0")
        zip_url = remote_info.get("zip_url", "")

        if remote_version != local_version and zip_url:
            # Preguntar al usuario antes de descargar
            response_event = asyncio.Event()
            proceed = False

            def on_yes(e):
                nonlocal proceed
                proceed = True
                dialog.open = False
                page.update()
                response_event.set()

            def on_no(e):
                nonlocal proceed
                proceed = False
                dialog.open = False
                page.update()
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

            page.overlay.append(dialog)
            dialog.open = True
            page.update()

            await response_event.wait()

            if dialog in page.overlay:
                page.overlay.remove(dialog)

            if not proceed:
                status_text.value = "Actualización omitida"
                page.update()
                await asyncio.sleep(0.5)
                return

            status_text.value = f"Descargando v{remote_version}..."
            page.update()

            # Descargar archivo temporal
            req_zip = urllib.request.Request(zip_url, headers={'User-Agent': 'Mozilla/5.0'})

            with urllib.request.urlopen(req_zip, timeout=60) as response_zip:
                total_size = int(response_zip.headers.get('content-length', 0))
                downloaded = 0
                block_size = 1024 * 8

                with open(zip_temp, 'wb') as out_file:
                    while True:
                        block = response_zip.read(block_size)
                        if not block:
                            break
                        downloaded += len(block)
                        out_file.write(block)

                        if total_size > 0:
                            percent = int(downloaded * 100 / total_size)
                            status_text.value = f"Descargando actualización ({percent}%)..."
                            page.update()

            status_text.value = "Instalando actualización..."
            page.update()

            # Descomprimir temporalmente
            if os.path.exists(temp_extract_dir):
                shutil.rmtree(temp_extract_dir)
            os.makedirs(temp_extract_dir)

            with zipfile.ZipFile(zip_temp, 'r') as zip_ref:
                zip_ref.extractall(temp_extract_dir)

            # Determinar ruta del contenido (por si GitHub mete todo en una carpeta raíz del repo)
            src_dir = temp_extract_dir
            subdirs = [os.path.join(temp_extract_dir, d) for d in os.listdir(temp_extract_dir) if os.path.isdir(os.path.join(temp_extract_dir, d))]
            if len(subdirs) == 1 and not os.path.exists(os.path.join(temp_extract_dir, "usr")):
                src_dir = subdirs[0]

            # Copiar carpeta usr (lógica de negocio)
            src_usr = os.path.join(src_dir, "usr")
            if os.path.exists(src_usr):
                dest_usr = os.path.join(updates_dir, "usr")
                if os.path.exists(dest_usr):
                    shutil.rmtree(dest_usr)
                shutil.copytree(src_usr, dest_usr)

            # Copiar carpeta config
            src_config = os.path.join(src_dir, "config")
            if os.path.exists(src_config):
                dest_config = os.path.join(updates_dir, "config")
                if os.path.exists(dest_config):
                    shutil.rmtree(dest_config)
                shutil.copytree(src_config, dest_config)

            # Guardar nueva versión localmente
            with open(version_path, "w", encoding="utf-8") as f:
                json.dump({"version": remote_version}, f)

            # Limpiar archivos temporales
            shutil.rmtree(temp_extract_dir)
            if os.path.exists(zip_temp):
                os.remove(zip_temp)

            status_text.value = f"¡Actualización v{remote_version} lista!"
            page.update()
            await asyncio.sleep(1)
        else:
            status_text.value = f"Aplicación al día (v{local_version})"
            page.update()
            await asyncio.sleep(0.5)

    except Exception as e:
        print(f"[UPDATER] Error al buscar/aplicar actualización: {e}")
        status_text.value = "Modo offline (omitiendo búsqueda)"
        page.update()
        await asyncio.sleep(1)
