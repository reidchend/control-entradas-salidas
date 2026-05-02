/**
 * Módulo de conexión a WhatsApp usando Baileys
 * Maneja la conexión, autenticación y envío de mensajes
 */

const { default: makeWASocket, DisconnectReason, useMultiFileAuthState } = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');
const fs = require('fs');
const path = require('path');
const QRCode = require('qrcode');

// Variable global para el socket
let sock = null;
let isConnected = false;
let isConnecting = false; // Evitar múltiples conexiones simultáneas
let currentQR = null; // Almacenar el QR actual

// Cargar configuración
const configPath = path.join(__dirname, 'config.json');
let config = { groupId: null };

if (fs.existsSync(configPath)) {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} else {
    fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
}

function saveConfig(newConfig) {
    config = { ...config, ...newConfig };
    fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
}

/**
 * Obtiene la lista de grupos disponibles
 */
async function getGroups() {
    if (!sock || !isConnected) {
        return null;
    }
    
    try {
        const groups = await sock.groupFetchAllParticipating();
        const groupList = Object.values(groups).map(g => ({
            id: g.id,
            name: g.subject,
            participants: g.participants.length
        }));
        return groupList;
    } catch (error) {
        console.error('Error al obtener grupos:', error);
        return [];
    }
}

/**
 * Configura el ID del grupo para enviar mensajes
 */
function setGroupId(groupId) {
    saveConfig({ groupId });
    console.log(`✅ Grupo configurado: ${groupId}`);
}

/**
 * Obtiene el ID del grupo actual
 */
function getGroupId() {
    return config.groupId;
}

/**
 * Envía un mensaje de texto a un grupo o número
 */
async function sendMessage(jid, message) {
    if (!sock || !isConnected) {
        throw new Error('WhatsApp no conectado');
    }
    
    try {
        await sock.sendMessage(jid, { text: message });
        console.log(`✅ Mensaje enviado a ${jid}`);
        return true;
    } catch (error) {
        console.error('Error enviando mensaje:', error);
        throw error;
    }
}

/**
 * Envía un mensaje al grupo configurado
 */
async function sendToGroup(message) {
    if (!config.groupId) {
        throw new Error('No hay grupo configurado. Usa setGroupId() o lista los grupos disponibles.');
    }
    return sendMessage(config.groupId, message);
}

/**
 * Conecta a WhatsApp con control de bucle
 */
async function connect() {
    // Evitar múltiples conexiones simultáneas
    if (isConnecting) {
        console.log('⏳ Conexión ya en progreso...');
        return sock;
    }
    
    isConnecting = true;
    const authPath = path.join(__dirname, 'auth');
    
    try {
        // Verificar que existe el directorio auth
        if (!fs.existsSync(authPath)) {
            fs.mkdirSync(authPath, { recursive: true });
        }
        
        const { state, saveCreds } = await useMultiFileAuthState(authPath);
        
        sock = makeWASocket({
            auth: state,
            printQRInTerminal: false, // Manejamos el QR manualmente
            browser: ["Ubuntu", "Chrome", "22.04.4"],
            syncFullHistory: false // Reducir uso de memoria
        });
        
        sock.ev.on('creds.update', saveCreds);
        
        sock.ev.on('connection.update', (update) => {
            const { connection, lastDisconnect, qr } = update;
            
            if (qr) {
                console.log('\n📱 NUEVO QR GENERADO - Visita: http://localhost:3000/qr');
                // Generar QR como data URL para servir via HTTP
                QRCode.toDataURL(qr, (err, url) => {
                    if (err) {
                        console.error('Error generando QR:', err);
                        return;
                    }
                    currentQR = url;
                });
            }
            
            if (connection === 'close') {
                const reason = new Boom(lastDisconnect?.error)?.output?.statusCode;
                const shouldReconnect = reason !== DisconnectReason.loggedOut;
                
                console.log(`❌ Conexión cerrada (${reason}). Reconectando: ${shouldReconnect}`);
                isConnected = false;
                sock = null;
                
                if (shouldReconnect) {
                    console.log('🔄 Reconectando en 5 segundos...');
                    setTimeout(() => {
                        isConnecting = false;
                        connect();
                    }, 5000); // Delay de 5 segundos
                } else {
                    isConnecting = false;
                }
            } else if (connection === 'open') {
                isConnected = true;
                isConnecting = false;
                console.log('✅ ¡Conectado a WhatsApp!\n');
                
                // Mostrar grupos disponibles
                setTimeout(async () => {
                    const groups = await getGroups();
                    if (groups && groups.length > 0) {
                        console.log('📋 Grupos disponibles:');
                        groups.forEach(g => {
                            console.log(`   - ${g.name} (${g.participants} participantes)`);
                            console.log(`     ID: ${g.id}`);
                        });
                        console.log('\n💡 Para configurar un grupo, usa: setGroupId("ID_DEL_GRUPO")');
                    }
                
                    if (config.groupId) {
                        console.log(`\n📢 Grupo configurado: ${config.groupId}`);
                    }
                }, 2000);
            }
        });
        
        return sock;
    } catch (error) {
        console.error('Error en connect():', error.message);
        isConnecting = false;
        throw error;
    }
}

/**
 * Verifica si está conectado
 */
function isWAConnected() {
    return isConnected;
}

module.exports = {
    connect,
    sendMessage,
    sendToGroup,
    getGroups,
    setGroupId,
    getGroupId,
    isConnected: isWAConnected,
    getCurrentQR: () => currentQR
};