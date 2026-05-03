/**
 * Servidor HTTP para el Bot de WhatsApp
 * Recibe mensajes de Python y los envía a través de Baileys
 */

const express = require('express');
const cors = require('cors');
const path = require('path');
const bot = require('./bot');

const app = express();
const PORT = process.env.PORT || 3000;
const AUTH_TOKEN = process.env.WHATSAPP_BOT_TOKEN || 'mi_token_secreto_123';

// Middleware
app.use(cors());
app.use(express.json());

// Middleware de autenticación (excepto para /qr)
app.use((req, res, next) => {
    // No requiere auth para la página del QR
    if (req.path === '/qr' || req.path === '/') {
        return next();
    }
    
    const token = req.headers['x-auth-token'] || req.query.token;
    if (!token || token !== AUTH_TOKEN) {
        return res.status(401).json({ error: 'Unauthorized - Token requerido' });
    }
    next();
});

// Middleware de logging
app.use((req, res, next) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
    next();
});

// Página HTML para mostrar el QR
app.get('/qr', (req, res) => {
    const qr = bot.getCurrentQR();
    const html = `
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WhatsApp Bot - QR Code</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 20px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 500px;
        }
        h1 {
            color: #25D366;
            margin-bottom: 10px;
        }
        .status {
            padding: 10px 20px;
            border-radius: 20px;
            display: inline-block;
            margin: 20px 0;
            font-weight: bold;
        }
        .connected {
            background: #d4edda;
            color: #155724;
        }
        .disconnected {
            background: #f8d7da;
            color: #721c24;
        }
        .qr-container {
            margin: 20px 0;
        }
        .qr-container img {
            max-width: 100%;
            height: auto;
            border: 3px solid #25D366;
            border-radius: 10px;
        }
        .message {
            color: #666;
            margin: 20px 0;
        }
        .refresh-btn {
            background: #25D366;
            color: white;
            border: none;
            padding: 10px 30px;
            border-radius: 25px;
            font-size: 16px;
            cursor: pointer;
            margin: 10px;
        }
        .refresh-btn:hover {
            background: #128C7E;
        }
        .info {
            background: #e7f3ff;
            padding: 15px;
            border-radius: 10px;
            margin: 20px 0;
            font-size: 14px;
            color: #004085;
        }
    </style>
    <script>
        function refreshQR() {
            location.reload();
        }
        // Auto-refresh cada 5 segundos si no está conectado
        setInterval(() => {
            fetch('/')
                .then(r => r.json())
                .then(data => {
                    if (!data.whatsapp_connected) {
                        location.reload();
                    }
                })
                .catch(() => {});
        }, 5000);
    </script>
</head>
<body>
    <div class="container">
        <h1>📱 WhatsApp Bot</h1>
        ${bot.isConnected() ? 
            '<div class="status connected">✅ Conectado</div>' : 
            '<div class="status disconnected">❌ No conectado</div>'
        }
        
        ${bot.isConnected() ? 
            '<p class="message">El bot está conectado y listo para usar.</p>' :
            (qr ? 
                `<div class="qr-container">
                    <img src="${qr}" alt="QR Code" />
                </div>
                <p class="message">Escanea este código con WhatsApp</p>
                <button class="refresh-btn" onclick="refreshQR()">🔄 Actualizar</button>` :
                '<p class="message">Generando QR... Por favor espera</p><button class="refresh-btn" onclick="refreshQR()">🔄 Actualizar</button>'
            )
        }
        
        ${bot.getGroupId() ? 
            `<div class="info">📢 Grupo configurado: ${bot.getGroupId()}</div>` : 
            ''
        }
        
        <div class="info">
            <strong>📋 Endpoints disponibles:</strong><br>
            POST /send - Enviar mensaje al grupo<br>
            GET /groups - Listar grupos<br>
            POST /set-group - Configurar grupo
        </div>
    </div>
</body>
</html>
    `;
    res.send(html);
});

// Endpoint de verificación de estado
app.get('/', (req, res) => {
    res.json({
        status: 'ok',
        whatsapp_connected: bot.isConnected(),
        group_id: bot.getGroupId()
    });
});

// Endpoint para enviar mensaje al grupo
app.post('/send', async (req, res) => {
    try {
        const { message } = req.body;
        
        if (!message) {
            return res.status(400).json({ error: 'El campo "message" es requerido' });
        }
        
        if (!bot.isConnected()) {
            return res.status(503).json({ error: 'WhatsApp no conectado' });
        }
        
        await bot.sendToGroup(message);
        
        res.json({ success: true, message: 'Mensaje enviado al grupo' });
    } catch (error) {
        console.error('Error:', error.message);
        res.status(500).json({ error: error.message });
    }
});

// Endpoint para enviar mensaje a un destinatario específico
app.post('/send-to', async (req, res) => {
    try {
        const { jid, message } = req.body;
        
        if (!jid || !message) {
            return res.status(400).json({ error: 'Los campos "jid" y "message" son requeridos' });
        }
        
        if (!bot.isConnected()) {
            return res.status(503).json({ error: 'WhatsApp no conectado' });
        }
        
        await bot.sendMessage(jid, message);
        
        res.json({ success: true, message: `Mensaje enviado a ${jid}` });
    } catch (error) {
        console.error('Error:', error.message);
        res.status(500).json({ error: error.message });
    }
});

// Endpoint para listar grupos disponibles
app.get('/groups', async (req, res) => {
    try {
        if (!bot.isConnected()) {
            return res.status(503).json({ error: 'WhatsApp no conectado' });
        }
        
        const groups = await bot.getGroups();
        res.json({ success: true, groups });
    } catch (error) {
        console.error('Error:', error.message);
        res.status(500).json({ error: error.message });
    }
});

// Endpoint para configurar el grupo
app.post('/set-group', (req, res) => {
    try {
        const { groupId } = req.body;
        
        if (!groupId) {
            return res.status(400).json({ error: 'El campo "groupId" es requerido' });
        }
        
        bot.setGroupId(groupId);
        
        res.json({ success: true, message: `Grupo configurado: ${groupId}` });
    } catch (error) {
        console.error('Error:', error.message);
        res.status(500).json({ error: error.message });
    }
});

// Endpoint para obtener la configuración actual
app.get('/config', (req, res) => {
    res.json({
        group_id: bot.getGroupId(),
        whatsapp_connected: bot.isConnected()
    });
});

// Iniciar servidor y conectar a WhatsApp
async function startServer() {
    console.log('🤖 Iniciando Bot de WhatsApp...\n');
    
    // Conectar a WhatsApp (no bloquea el servidor si falla)
    bot.connect().then(() => {
        console.log('✅ Cliente WhatsApp conectado\n');
    }).catch(error => {
        console.error('❌ Error conectando a WhatsApp:', error.message);
        console.log('💡 El servidor sigue corriendo. El bot reintentará conectar automáticamente.\n');
    });
    
    // Iniciar servidor HTTP inmediatamente en todas las interfaces
    app.listen(PORT, '0.0.0.0', () => {
        console.log(`
╔══════════════════════════════════════════════════╗
║           🤖 SERVIDOR DE BOT WHATSAPP              ║
╠══════════════════════════════════════════════════╣
║  Servidor:     http://0.0.0.0:${PORT} (todas las interfaces) ║
║  QR Page:      http://localhost:${PORT}/qr           ║
║  Estado:       ${bot.isConnected() ? '✅ Conectado' : '❌ Desconectado'}
║  Grupo:        ${bot.getGroupId() || '❌ No configurado'}
╠══════════════════════════════════════════════════╣
║  Endpoints disponibles:                            ║
║  - GET  /qr          → Ver código QR                ║
║  - POST /send        → Enviar mensaje al grupo     ║
║  - POST /send-to     → Enviar a destinatario       ║
║  - GET  /groups      → Listar grupos               ║
║  - POST /set-group   → Configurar grupo            ║
║  - GET  /config      → Ver configuración           ║
╚══════════════════════════════════════════════════╝
`);
        console.log('⚠️  Token configurado:', AUTH_TOKEN !== 'mi_token_secreto_123' ? 'Personalizado' : 'Default (cámbialo con WHATSAPP_BOT_TOKEN)');
    });
}

// Iniciar
startServer();
