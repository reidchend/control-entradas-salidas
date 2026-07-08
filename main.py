import os
import sys
import ssl
import certifi

os.environ['SSL_CERT_FILE'] = certifi.where()


def resource_path(relative_path: str) -> str:
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), relative_path)


import flet as ft
from usr.app_launcher import main

if __name__ == "__main__":
    ft.app(target=main, assets_dir=resource_path("assets"))
