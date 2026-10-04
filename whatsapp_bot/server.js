/**
 * Servidor HTTP para el Bot de WhatsApp
 * Recibe mensajes de Python y los envía a través de Baileys
 */

const express = require('express');
const cors = require('cors');
const path = require('path');
const bot = require('./bot');
const descargarImagen = require('./descargar_imagen');

const app = express();
const PORT = process.env.PORT || 3000;

// Token obligatorio para /send, /config, etc. Ya no existe un default de
// respaldo: el que venía en el repo era público y cualquiera podía llamar
// al bot. Micho el proceso si falta, para que el fallo sea visible en los
// logs en vez de aceptar envíos con un token conocido.
if (!process.env.WHATSAPP_BOT_TOKEN) {
    console.error(
        'ERROR: falta WHATSAPP_BOT_TOKEN. Generalo y agregalo al .env ' +
        '(ver .env.example). El bot no arranca sin un token propio.'
    );
    process.exit(1);
}
const AUTH_TOKEN = process.env.WHATSAPP_BOT_TOKEN;

// Middleware
app.use(cors());

// Límite del cuerpo JSON. Sin `limit`, body-parser corta en 102400 bytes (100kb),
// y una imagen llega como base64: se infla ~33% contra el archivo original. Con
// el default, cualquier foto o captura de más de ~76 KB daba 413 y la app
// Flutter no lo veía (por debajo solo comparaba `statusCode == 200`).
// 25mb cubre de sobra una imagen de 16 MB en base64, que es el máximo que
// acepta WhatsApp.
app.use(express.json({ limit: '25mb' }));

// Header anti-interstitial ngrok
app.use((req, res, next) => {
    res.setHeader('ngrok-skip-browser-warning', 'true');
    next();
});

// Middleware de autenticación (excepto para /qr)
app.use((req, res, next) => {
    // No requiere auth para la página del QR
    if (req.path === '/qr' || req.path === '/' || req.path === '/panel') {
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
        ${bot.getReportGroupId() ? 
            `<div class="info">📊 Grupo de reportes: ${bot.getReportGroupId()}</div>` : 
            ''
        }
        
        <div class="info">
            <strong>📋 Endpoints disponibles:</strong><br>
            POST /send          → Enviar mensaje al grupo<br>
            POST /send-image    → Enviar imagen con caption al grupo<br>
            POST /send-to       → Enviar a destinatario       <br>
            GET  /groups        → Listar grupos               <br>
            POST /set-group     → Configurar grupo            <br>
            POST /set-report-group → Configurar grupo reportes<br>
            POST /send-report   → Enviar reporte (texto)      <br>
            POST /send-document → Enviar documento .txt       <br>
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
        group_id: bot.getGroupId(),
        report_group_id: bot.getReportGroupId()
    });
});

// Panel de control
app.get('/panel', (req, res) => {
    const panelPath = path.join(__dirname, 'panel_bot.html');
    res.sendFile(panelPath);
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

// Endpoint para enviar imagen con caption al grupo
app.post('/send-image', async (req, res) => {
    try {
        // imageUrl es lo que manda el panel web. imageBase64 es lo que manda la
        // app Flutter. imagePath lo que mandaba uno a mano desde el server.
        // Antes solo se leian los dos ultimos, y el panel por eso nunca pudo
        // mandar una imagen: caia en el 400 de "se requiere imagePath".
        const { caption, imageUrl, imagePath, imageBase64 } = req.body;

        if (!imageUrl && !imagePath && !imageBase64) {
            return res.status(400).json({
                error: 'Se requiere "imageUrl", "imagePath" o "imageBase64"'
            });
        }

        if (!bot.isConnected()) {
            return res.status(503).json({ error: 'WhatsApp no conectado' });
        }

        let imageBuffer;
        if (imageBase64) {
            imageBuffer = Buffer.from(imageBase64, 'base64');
        } else if (imageUrl) {
            const bajada = await descargarImagen.descargar(imageUrl);
            imageBuffer = bajada.buffer;
        } else {
            const fs = require('fs');
            if (!fs.existsSync(imagePath)) {
                return res.status(400).json({ error: 'Archivo de imagen no encontrado: ' + imagePath });
            }
            imageBuffer = fs.readFileSync(imagePath);
        }

        await bot.sendImageToGroup(imageBuffer, caption || '');

        res.json({ success: true, message: 'Imagen enviada al grupo' });
    } catch (error) {
        console.error('Error:', error.message);
        // descargarImagen marca con .status los errores que son culpa de lo que
        // se mando (URL rota, no es imagen, demasiado pesada). Esos son 400 y no
        // 500: el server esta bien, lo que estaba mal era el pedido.
        res.status(error.status || 500).json({ error: error.message });
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

// Endpoint para configurar el grupo de reportes
app.post('/set-report-group', (req, res) => {
    try {
        const { reportGroupId } = req.body;
        
        if (!reportGroupId) {
            return res.status(400).json({ error: 'El campo "reportGroupId" es requerido' });
        }
        
        bot.setReportGroupId(reportGroupId);
        
        res.json({ success: true, message: `Grupo de reportes configurado: ${reportGroupId}` });
    } catch (error) {
        console.error('Error:', error.message);
        res.status(500).json({ error: error.message });
    }
});

// Endpoint para enviar un mensaje de texto al grupo de reportes
app.post('/send-report', async (req, res) => {
    try {
        const { message } = req.body;
        
        if (!message) {
            return res.status(400).json({ error: 'El campo "message" es requerido' });
        }
        
        if (!bot.isConnected()) {
            return res.status(503).json({ error: 'WhatsApp no conectado' });
        }
        
        await bot.sendReportToGroup(message);
        
        res.json({ success: true, message: 'Reporte enviado al grupo de reportes' });
    } catch (error) {
        console.error('Error:', error.message);
        res.status(500).json({ error: error.message });
    }
});

// Endpoint para enviar un documento (.txt) al grupo de reportes
app.post('/send-document', async (req, res) => {
    try {
        const { fileName, content, caption } = req.body;
        
        if (!fileName || content === undefined || content === null) {
            return res.status(400).json({ error: 'Los campos "fileName" y "content" son requeridos' });
        }
        
        if (!bot.isConnected()) {
            return res.status(503).json({ error: 'WhatsApp no conectado' });
        }
        
        const buffer = Buffer.from(String(content), 'utf8');
        await bot.sendDocumentToGroup(buffer, fileName, caption || '');
        
        res.json({ success: true, message: `Documento enviado: ${fileName}` });
    } catch (error) {
        console.error('Error:', error.message);
        res.status(500).json({ error: error.message });
    }
});

// Endpoint para obtener la configuración actual
app.get('/config', async (req, res) => {
    const groupId = bot.getGroupId();
    let group = null;
    if (groupId && bot.isConnected()) {
        group = await bot.getGroupMetadata(groupId);
    }
    const reportGroupId = bot.getReportGroupId();
    let reportGroup = null;
    if (reportGroupId && bot.isConnected()) {
        reportGroup = await bot.getGroupMetadata(reportGroupId);
    }
    res.json({
        group_id: groupId,
        group_name: group ? group.name : null,
        group_participants: group ? group.participants : null,
        report_group_id: reportGroupId,
        report_group_name: reportGroup ? reportGroup.name : null,
        whatsapp_connected: bot.isConnected()
    });
});

// Handler de errores de alcance general. Tiene que ir DESPUÉS de las rutas:
// Express lo busca entre los handlers registrados después del punto del fallo.
//
// Sin esto, un error de body-parser (por ejemplo 413 por body demasiado grande)
// salía como una página HTML vacía y sin logear: los `console.error` que hay en
// los endpoints viven dentro de su propio try/catch, que nunca se ejecutaba
// porque el body se rechazaba antes de entrar a la ruta. Por eso un 413 se
// veía desde la app como un simple "no se envió", sin causa.
app.use((err, req, res, next) => {
    const status = err.status || err.statusCode || 500;
    if (status === 413) {
        console.error(
            `❌ 413 body demasiado grande en ${req.method} ${req.originalUrl}: ` +
            `recibidos ${req.headers['content-length'] || '?'} bytes, ` +
            `limite ${err.limit || '?'}. Si es una imagen, suele ser que el ` +
            `cliente manda un base64 sin comprimir.`
        );
    } else {
        console.error(`❌ Error no manejado en ${req.method} ${req.originalUrl}:`, err.message);
    }
    if (res.headersSent) return next(err);
    res.status(status).json({ error: err.message || 'Error interno' });
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
        console.log('✅  Token configurado (WHATSAPP_BOT_TOKEN).');
    });
}

// Iniciar
startServer();
