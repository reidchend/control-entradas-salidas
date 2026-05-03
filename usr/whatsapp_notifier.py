"""
Módulo para enviar notificaciones a WhatsApp desde Python
Uso el servidor Node.js corriendo en localhost:3000 o URL configurada
"""
import requests
import json
import os


# URL configurable via variable de entorno
WHATSAPP_BOT_URL = os.getenv("WHATSAPP_BOT_URL", "http://localhost:3000")
# Token de autenticación (debe coincidir con WHATSAPP_BOT_TOKEN en server.js)
WHATSAPP_BOT_TOKEN = os.getenv("WHATSAPP_BOT_TOKEN", "mi_token_secreto_123")


def send_whatsapp_message(message: str) -> bool:
    """
    Envía un mensaje al grupo configurado en el bot de WhatsApp
    
    Args:
        message: Texto del mensaje a enviar
        
    Returns:
        True si se envió correctamente, False si hubo error
    """
    try:
        headers = {'x-auth-token': WHATSAPP_BOT_TOKEN}
        response = requests.post(
            f"{WHATSAPP_BOT_URL}/send",
            json={"message": message},
            headers=headers,
            timeout=10
        )
        
        if response.status_code == 200:
            print(f"✅ WhatsApp: Mensaje enviado - {message[:50]}...")
            return True
        else:
            print(f"❌ WhatsApp Error: {response.status_code} - {response.text}")
            return False
            
    except requests.exceptions.ConnectionError:
        print("❌ WhatsApp Bot no disponible (¿Está corriendo en localhost:3000?)")
        return False
    except Exception as e:
        print(f"❌ WhatsApp Error: {e}")
        return False


def send_whatsapp_to(jid: str, message: str) -> bool:
    """
    Envía un mensaje a un destinatario específico (número o grupo)
    
    Args:
        jid: WhatsApp ID (ej: "1234567890@s.whatsapp.net" o "123456789-123@g.us")
        message: Texto del mensaje
    """
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
    """
    Obtiene el estado actual del bot de WhatsApp
    
    Returns:
        Diccionario con 'whatsapp_connected' y 'group_id'
    """
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
    """
    Obtiene la lista de grupos disponibles
    
    Returns:
        Lista de grupos con 'id', 'name', 'participants'
    """
    try:
        response = requests.get(f"{WHATSAPP_BOT_URL}/groups", 
                               headers={'x-auth-token': WHATSAPP_BOT_TOKEN}, 
                               timeout=5)
        if response.status_code == 200:
            return response.json().get('groups', [])
        return []
    except:
        return []


def format_validation_message(producto_nombre: str, cantidad: float, factura: str, proveedor: str = "Varios") -> str:
    """
    Formatea un mensaje de validación de entrada para WhatsApp
    """
    return f"""✅ *Entrada Validada* ✅

📦 *Producto:* {producto_nombre}
📊 *Cantidad:* {cantidad}
📃 *Factura:* {factura}
🏢 *Proveedor:* {proveedor}
🕐 *Fecha:* {__import__('datetime').datetime.now().strftime('%d/%m %H:%M')}

_Inventario Lycoris_"""


# Ejemplo de uso
if __name__ == "__main__":
    print("=== Prueba de WhatsApp Bot ===")
    
    # Verificar estado
    status = get_whatsapp_status()
    print(f"Estado: {status}")
    
    # Enviar mensaje de prueba
    if status.get('whatsapp_connected'):
        msg = format_validation_message("Producto de Prueba", 50, "FAC-001", "Proveedor Test")
        send_whatsapp_message(msg)
    else:
        print("⚠️ WhatsApp no conectado. Inicia el bot primero.")
