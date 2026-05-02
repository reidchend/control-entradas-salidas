/**
 * Servidor HTTP para el Bot de WhatsApp
 * Recibe mensajes de Python y los envía a través de Baileys
 */

const express = require('express');
const cors = require('cors');
const bot = require('./bot');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Middleware de logging
app.use((req, res, next) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
    next();
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
    
    // Conectar a WhatsApp
    try {
        await bot.connect();
        console.log('✅ Cliente WhatsApp conectado\n');
    } catch (error) {
        console.error('❌ Error conectando a WhatsApp:', error.message);
    }
    
    // Iniciar servidor HTTP
    app.listen(PORT, () => {
        console.log(`
╔════════════════════════════════════════════════════╗
║           🤖 SERVIDOR DE BOT WHATSAPP              ║
╠════════════════════════════════════════════════════╣
║  Servidor:     http://localhost:${PORT}             ║
║  Estado:       ${bot.isConnected() ? '✅ Conectado' : '❌ Desconectado'}
║  Grupo:        ${bot.getGroupId() || '❌ No configurado'}
╠════════════════════════════════════════════════════╣
║  Endpoints disponibles:                            ║
║  - POST /send        → Enviar mensaje al grupo     ║
║  - POST /send-to     → Enviar a destinatario       ║
║  - GET  /groups      → Listar grupos               ║
║  - POST /set-group   → Configurar grupo            ║
║  - GET  /config      → Ver configuración           ║
╚════════════════════════════════════════════════════╝
`);
    });
}

// Iniciar
startServer();