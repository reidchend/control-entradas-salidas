"""
Manejo de callbacks de sincronización entre vistas.
"""
from typing import List, Callable

_sync_callbacks: List[Callable] = []

def register_sync_callback(callback: Callable):
    """Registra un callback que se ejecuta después de cada sync."""
    if callback not in _sync_callbacks:
        _sync_callbacks.append(callback)

def unregister_sync_callback(callback: Callable):
    """Elimina un callback registrado."""
    if callback in _sync_callbacks:
        _sync_callbacks.remove(callback)

def notify_sync_complete():
    """Notifica a todos los callbacks registrados."""
    import traceback
    if _sync_callbacks:  # Solo loguear si hay callbacks
        print(f"[SYNC CB] Notificando a {len(_sync_callbacks)} callbacks")
    for callback in _sync_callbacks:
        try:
            callback()
        except Exception as e:
            print(f"[SYNC CB] Error en callback: {e}")
            traceback.print_exc()

def clear_all_callbacks():
    """Limpia todos los callbacks registrados."""
    _sync_callbacks.clear()