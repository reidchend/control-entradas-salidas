/**
 * Servidor de prueba SIN WhatsApp para Codespace
 * Solo simula las respuestas
 */

const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Endpoint de verificación de estado
app.get('/', (req, res) => {
    res.json({
        status: 'ok',
        whatsapp_connected: false,
        mode: 'test (no WhatsApp in Codespace)',
        group_id: 'test-group'
    });
});

// Endpoint para enviar mensaje al grupo (simulado)
app.post('/send', async (req, res) => {
    const { message } = req.body;
    
    if (!message) {
        return res.status(400).json({ error: 'El campo "message" es requerido' });
    }
    
    console.log(`[TEST] Mensaje que se enviaría: ${message}`);
    
    res.json({ 
        success: true, 
        message: 'Mensaje simulado (WhatsApp no disponible en Codespace)',
        note: 'Para usar con WhatsApp real, ejecutar en máquina local'
    });
});

// Endpoint para configurar grupo (simulado)
app.post('/set-group', (req, res) => {
    const { groupId } = req.body;
    console.log(`[TEST] Grupo configurado: ${groupId}`);
    res.json({ success: true, message: `Grupo simulado: ${groupId}` });
});

// Iniciar servidor
app.listen(PORT, () => {
    console.log(`
╔════════════════════════════════════════════════════╗
║         🤖 SERVIDOR DE PRUEBA (CODESPACE)          ║
╠════════════════════════════════════════════════════╣
║  Servidor:     http://localhost:${PORT}             ║
║  Modo:         Solo prueba (sin WhatsApp)           ║
╠════════════════════════════════════════════════════╣
║  Endpoints:                                        ║
║  - GET  /         → Estado del servidor            ║
║  - POST /send     → Simula envío de mensaje         ║
║  - POST /set-group→ Simula config de grupo          ║
╚════════════════════════════════════════════════════╝

Para usar WhatsApp real, clona el repo en tu máquina local.
`);
});
