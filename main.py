import os
import sys
import ssl
import certifi

os.environ['SSL_CERT_FILE'] = certifi.where()


def resource_path(relative_path: str) -> str:
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), relative_path)


_app_dir = os.path.dirname(os.path.abspath(__file__))
_updates_dir = os.path.join(_app_dir, "app_updates")
if os.path.exists(_updates_dir):
    sys.path.insert(0, _updates_dir)

os.environ['LYCORIS_DB_PATH'] = os.path.join(_app_dir, "lycoris_local.db")

import asyncio
import flet as ft
import usr.app_launcher

async def main(page: ft.Page) -> None:
    await usr.app_launcher.main(page)

if __name__ == "__main__":
    ft.app(target=main, assets_dir=resource_path("assets"))
