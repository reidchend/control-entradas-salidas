import flet as ft
import inspect
import os

def verify():
    # 1. ¿De dónde se está cargando Flet?
    print(f"📍 Ruta de Flet: {inspect.getfile(ft)}")
    
    # 2. ¿Qué tiene adentro?
    members = dir(ft)
    print(f"🔍 ¿Tiene atributo 'Page'?: {'Page' in members}")
    
    # 3. Intentar encontrar FCM de forma agresiva
    fcm_found = False
    if "fcm" in members:
        fcm_found = True
        print("✅ FCM encontrado como atributo directo de flet.")
    
    try:
        from flet import fcm
        fcm_found = True
        print("✅ FCM encontrado como submódulo.")
    except ImportError:
        pass

    if not fcm_found:
        print("❌ FCM NO encontrado. Probablemente falte el plugin de Flutter.")

if __name__ == "__main__":
    verify()