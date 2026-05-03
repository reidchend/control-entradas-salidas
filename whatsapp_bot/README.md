# WhatsApp Bot - Guía de Configuración

## Descripción
Bot de WhatsApp usando Baileys que recibe mensajes via HTTP y los envía a grupos de WhatsApp.

## Requisitos
- Node.js >= 18
- npm
- Cuenta de WhatsApp con QR de vinculación
- ngrok (para acceso desde internet)

## Instalación

### 1. Instalar dependencias
```bash
cd whatsapp_bot
rm -rf node_modules package-lock.json auth
npm install @whiskeysockets/baileys@latest
npm install qrcode express cors
```

### 2. Configurar Token de Seguridad
```bash
# Linux/Mac
export WHATSAPP_BOT_TOKEN="tu_token_secreto_aqui"

# Windows (cmd)
set WHATSAPP_BOT_TOKEN=tu_token_secreto_aqui

# Windows (PowerShell)
$env:WHATSAPP_BOT_TOKEN="tu_token_secreto_aqui"
```

### 3. Iniciar el Bot
```bash
node server.js
```

### 4. Vincular WhatsApp
1. Abre en tu navegador: `http://localhost:3000/qr`
2. En tu teléfono: WhatsApp → Configuración → Dispositivos vinculados → Vincular dispositivo
3. Escanea el código QR

### 5. Configurar ngrok para Internet

#### Instalar ngrok:
```bash
# Linux
curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt update && sudo apt install ngrok

# Windows (Chocolatey)
choco install ngrok

# O descarga manual: https://ngrok.com/download
```

#### Configurar authtoken (gratis):
1. Regístrate en https://ngrok.com
2. Obtén tu authtoken
3. Configura: `ngrok config add-authtoken TU_TOKEN`

#### Ejecutar ngrok:
```bash
ngrok http 3000
```
Obtendrás una URL como: `https://abc123.ngrok.io`

### 6. Configurar la App Python

En `usr/whatsapp_notifier.py` o en `.env`:
```bash
# Linux/Mac
export WHATSAPP_BOT_URL="https://abc123.ngrok.io"
export WHATSAPP_BOT_TOKEN="tu_token_secreto_aqui"

# Windows (cmd)
set WHATSAPP_BOT_URL=https://abc123.ngrok.io
set WHATSAPP_BOT_TOKEN=tu_token_secreto_aqui
```

O edita `usr/whatsapp_notifier.py`:
```python
WHATSAPP_BOT_URL = "https://abc123.ngrok.io"  # URL de ngrok
WHATSAPP_BOT_TOKEN = "tu_token_secreto_aqui"
```

## Uso

### Configurar Grupo
```bash
# Listar grupos disponibles
curl http://localhost:3000/groups

# Configurar grupo (usar ID de la lista anterior)
curl -X POST http://localhost:3000/set-group \
  -H "Content-Type: application/json" \
  -H "x-auth-token: tu_token_secreto_aqui" \
  -d '{"groupId": "584149977245-1609193491@g.us"}'
```

### Enviar Mensaje de Prueba
```bash
curl -X POST http://localhost:3000/send \
  -H "Content-Type: application/json" \
  -H "x-auth-token: tu_token_secreto_aqui" \
  -d '{"message": "🎉 ¡Prueba exitosa!"}'
```

### Desde Python
```python
from usr.whatsapp_notifier import send_whatsapp_message, format_validation_message

msg = format_validation_message("Producto X", 50, "FAC-001", "Proveedor Y")
send_whatsapp_message(msg)
```

## Solución de Problemas

### Error 405 al conectar
- ✅ El código actual usa `fetchLatestBaileysVersion()` y `Browsers.macOS('Chrome')`
- Borra la carpeta `auth` y vuelve a intentar

### No recibo mensajes
1. Verifica estado: `curl http://localhost:3000/`
2. Verifica que el grupo esté configurado
3. Revisa los logs del servidor

### ngrok da error de auth
- Verifica que hayas configurado el authtoken: `ngrok config check`
- Reinicia ngrok después de configurar

## Endpoints Disponibles

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| GET | `/` | Estado del bot |
| GET | `/qr` | Página del código QR |
| POST | `/send` | Enviar mensaje al grupo configurado |
| POST | `/send-to` | Enviar a destinatario específico |
| GET | `/groups` | Listar grupos disponibles |
| POST | `/set-group` | Configurar grupo |
| GET | `/config` | Ver configuración actual |

**Nota:** Todos los endpoints excepto `/` y `/qr` requieren header `x-auth-token`.
