"""
Módulo para enviar notificaciones a WhatsApp desde Python
Uso el servidor Node.js corriendo en localhost:3000 o URL configurada
"""
import requests
import json
import os
import base64
import sqlite3
import threading
import time
from datetime import datetime

WHATSAPP_BOT_URL = "https://lycorys-control.shares.zrok.io"
WHATSAPP_BOT_TOKEN = "mi_token_secreto_123"


# ==================== COLA DE WHATSAPP ====================

def _get_queue_conn():
    from usr.database.local_replica import get_local_conn
    return get_local_conn()


def save_to_queue(tipo: str, mensaje: str = "", imagen_path: str = None, imagen_base64: str = None):
    conn = _get_queue_conn()
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO whatsapp_queue (tipo, mensaje, imagen_base64, imagen_path, estado, created_at)
            VALUES (?, ?, ?, ?, 'pending', datetime('now', 'localtime'))
        """, (tipo, mensaje, imagen_base64, imagen_path))
        conn.commit()
        print(f"[WA QUEUE] Guardado en cola: {tipo} - {mensaje[:50] if mensaje else 'imagen'}")
    except Exception as e:
        print(f"[WA QUEUE] Error guardando en cola: {e}")
    finally:
        conn.close()


def get_queued_messages(estado: str = None, limit: int = 50) -> list:
    conn = _get_queue_conn()
    cursor = conn.cursor()
    try:
        if estado:
            cursor.execute("""
                SELECT * FROM whatsapp_queue WHERE estado = ? ORDER BY created_at DESC LIMIT ?
            """, (estado, limit))
        else:
            cursor.execute("""
                SELECT * FROM whatsapp_queue ORDER BY created_at DESC LIMIT ?
            """, (limit,))
        rows = cursor.fetchall()
        columns = [desc[0] for desc in cursor.description]
        return [dict(zip(columns, row)) for row in rows]
    except Exception as e:
        print(f"[WA QUEUE] Error leyendo cola: {e}")
        return []
    finally:
        conn.close()


def count_pending() -> int:
    conn = _get_queue_conn()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT COUNT(*) FROM whatsapp_queue WHERE estado = 'pending' AND intentos < max_intentos")
        return cursor.fetchone()[0]
    except Exception as e:
        return 0
    finally:
        conn.close()


def retry_queued_messages():
    conn = _get_queue_conn()
    cursor = conn.cursor()
    try:
        cursor.execute("""
            SELECT * FROM whatsapp_queue 
            WHERE estado IN ('pending', 'failed') AND intentos < max_intentos
            ORDER BY created_at ASC LIMIT 10
        """)
        rows = cursor.fetchall()
        columns = [desc[0] for desc in cursor.description]
        messages = [dict(zip(columns, row)) for row in rows]
    except Exception as e:
        err = str(e)
        if "no such table" not in err:
            print(f"[WA QUEUE] Error leyendo cola para reintentar: {e}")
        conn.close()
        return
    finally:
        conn.close()

    for msg in messages:
        try:
            success = False
            if msg['tipo'] == 'text':
                success = _send_text_direct(msg['mensaje'])
            elif msg['tipo'] == 'image':
                success = _send_image_direct(msg['imagen_base64'], msg['mensaje'], msg['imagen_path'])

            conn = _get_queue_conn()
            cursor = conn.cursor()
            if success:
                cursor.execute("""
                    UPDATE whatsapp_queue SET estado = 'sent', updated_at = datetime('now', 'localtime')
                    WHERE id = ?
                """, (msg['id'],))
                print(f"[WA QUEUE] Mensaje {msg['id']} enviado exitosamente")
            else:
                cursor.execute("""
                    UPDATE whatsapp_queue SET 
                        intentos = intentos + 1, 
                        estado = CASE WHEN intentos + 1 >= max_intentos THEN 'failed' ELSE 'pending' END,
                        ultimo_error = 'Error de conexión',
                        updated_at = datetime('now', 'localtime')
                    WHERE id = ?
                """, (msg['id'],))
            conn.commit()
            conn.close()
        except Exception as e:
            print(f"[WA QUEUE] Error reintentando mensaje {msg['id']}: {e}")


def _send_text_direct(message: str) -> bool:
    try:
        headers = {'x-auth-token': WHATSAPP_BOT_TOKEN}
        response = requests.post(
            f"{WHATSAPP_BOT_URL}/send",
            json={"message": message},
            headers=headers,
            timeout=10
        )
        return response.status_code == 200
    except requests.exceptions.ConnectionError:
        return False
    except Exception as e:
        print(f"[WA] Error directo texto: {e}")
        return False


def _send_image_direct(img_b64: str, caption: str, img_path: str = None) -> bool:
    try:
        if not img_b64 and img_path:
            if os.path.exists(img_path):
                with open(img_path, 'rb') as f:
                    img_b64 = base64.b64encode(f.read()).decode('utf-8')
            else:
                return False
        if not img_b64:
            return False
        headers = {'x-auth-token': WHATSAPP_BOT_TOKEN, 'Content-Type': 'application/json'}
        payload = {'imageBase64': img_b64, 'caption': caption or ''}
        response = requests.post(f"{WHATSAPP_BOT_URL}/send-image", json=payload, headers=headers, timeout=30)
        return response.status_code == 200
    except requests.exceptions.ConnectionError:
        return False
    except Exception as e:
        print(f"[WA] Error directo imagen: {e}")
        return False


# ==================== HILO DE REINTENTO BACKGROUND ====================

_retry_thread_started = False

def _start_retry_thread():
    global _retry_thread_started
    if _retry_thread_started:
        return
    _retry_thread_started = True

    def loop():
        while True:
            try:
                retry_queued_messages()
            except Exception:
                pass
            time.sleep(60)

    t = threading.Thread(target=loop, daemon=True)
    t.start()
    print("[WA QUEUE] Hilo de reintentos iniciado")


# ==================== ENVIAR CON COLA ====================

def _send_with_queue(func_direct, tipo, *args, **kwargs):
    try:
        result = func_direct(*args, **kwargs)
        if result:
            return True
    except Exception:
        pass

    # Si falló, guardar en cola
    try:
        if tipo == 'text':
            mensaje = args[0] if args else kwargs.get('message', '')
            save_to_queue('text', mensaje=mensaje)
        elif tipo == 'image':
            img_path = args[0] if args else kwargs.get('image_path', '')
            caption = kwargs.get('caption', '')
            img_b64 = None
            if img_path and os.path.exists(img_path):
                with open(img_path, 'rb') as f:
                    img_b64 = base64.b64encode(f.read()).decode('utf-8')
            save_to_queue('image', mensaje=caption, imagen_path=img_path, imagen_base64=img_b64)
    except Exception as e:
        print(f"[WA QUEUE] Error guardando en cola fallback: {e}")
    return False


def send_whatsapp_message(message: str) -> bool:
    return _send_with_queue(_send_text_direct, 'text', message)


def send_whatsapp_image(image_path: str, caption: str = "") -> bool:
    try:
        img_b64 = None
        if image_path and os.path.exists(image_path):
            with open(image_path, 'rb') as f:
                img_b64 = base64.b64encode(f.read()).decode('utf-8')

        if _send_image_direct(img_b64, caption):
            return True

        if img_b64:
            save_to_queue('image', mensaje=caption, imagen_path=image_path, imagen_base64=img_b64)
        else:
            print(f"[WA] Imagen no encontrada, guardando caption: {image_path}")
            save_to_queue('text', mensaje=caption)
        return False
    except Exception as e:
        print(f"[WA] Error en send_whatsapp_image: {e}")
        save_to_queue('text', mensaje=caption)
        return False


# ==================== FUNCIONES ORIGINALES ====================

def send_whatsapp_to(jid: str, message: str) -> bool:
    try:
        headers = {'x-auth-token': WHATSAPP_BOT_TOKEN}
        response = requests.post(
            f"{WHATSAPP_BOT_URL}/send-to",
            json={"jid": jid, "message": message},
            headers=headers,
            timeout=10
        )
        if response.status_code == 200:
            print(f"✅ WhatsApp: Mensaje enviado a {jid}")
            return True
        else:
            print(f"❌ WhatsApp Error: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ WhatsApp Error: {e}")
        return False


def get_whatsapp_status() -> dict:
    try:
        response = requests.get(f"{WHATSAPP_BOT_URL}/config", 
                               headers={'x-auth-token': WHATSAPP_BOT_TOKEN}, 
                               timeout=5)
        if response.status_code == 200:
            return response.json()
        return {"whatsapp_connected": False, "group_id": None}
    except:
        return {"whatsapp_connected": False, "group_id": None}


def get_available_groups() -> list:
    try:
        response = requests.get(f"{WHATSAPP_BOT_URL}/groups", 
                               headers={'x-auth-token': WHATSAPP_BOT_TOKEN}, 
                               timeout=5)
        if response.status_code == 200:
            return response.json().get('groups', [])
        return []
    except:
        return []


def format_validation_message(producto_nombre: str, cantidad: float, factura: str, 
                               proveedor: str = "Varios", monto: float = 0, 
                               metodos_pago: list = None, usuario: str = "") -> str:
    import datetime
    return f"""✅ *Entrada Validada* ✅

📦 *Cargo productos:* {producto_nombre}
🏢 *Proveedor:* {proveedor}
📃 *Factura:* {factura}
🕐 *Fecha:* {datetime.datetime.now().strftime('%d/%m %H:%M')}
👤 *Usuario:* {usuario}

_🤖-Lycoris_bot_"""


def delete_from_queue(msg_id: int):
    conn = _get_queue_conn()
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM whatsapp_queue WHERE id = ?", (msg_id,))
        conn.commit()
    except Exception as e:
        print(f"[WA QUEUE] Error eliminando mensaje {msg_id}: {e}")
    finally:
        conn.close()


def update_queue_estado(msg_id: int, estado: str, error: str = None):
    conn = _get_queue_conn()
    cursor = conn.cursor()
    try:
        cursor.execute("""
            UPDATE whatsapp_queue SET estado = ?, ultimo_error = ?, updated_at = datetime('now', 'localtime')
            WHERE id = ?
        """, (estado, error, msg_id))
        conn.commit()
    except Exception as e:
        print(f"[WA QUEUE] Error actualizando estado {msg_id}: {e}")
    finally:
        conn.close()


# Iniciar hilo background automáticamente
_start_retry_thread()
