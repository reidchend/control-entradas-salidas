/**
 * Descarga una imagen desde una URL HTTP(S) para mandarla al grupo.
 *
 * Existe por un desajuste de nombres entre el panel y el servidor. El panel
 * (panel_bot.html) pide una URL, porque su input es type="url", y manda
 * {"imageUrl": ..., "caption": ...}. Pero /send-image solo desestructuraba
 * {caption, imagePath, imageBase64}: imageUrl llegaba descartado, los dos
 * campos que sí leían quedaban en undefined, y la respuesta era siempre
 * 400 "Se requiere imagePath o imageBase64". Ninguna combinacion de valores
 * funcionaba, porque el panel nunca mandaba los nombres que el servidor
 * buscaba. La app Flutter no lo sufria porque va por imageBase64.
 *
 * Por que no convertir la URL a base64 en el navegador: el panel no puede
 * leer el cuerpo de un fetch a otro dominio si el servidor de imagenes no
 * manda CORS, y casi ninguno lo hace. Descargar del lado del servidor es lo
 * unico que funciona con cualquier host.
 *
 * Por que el modulo https en vez de fetch: con fetch habia que buffersizar la
 * respuesta entera y recien ahi comprobar el peso, asi que una URL enorme se
 * bajaba completa antes de rechazar el envio. Con https se corta en caliente.
 */

const http = require('http');
const https = require('https');

// WhatsApp no acepta imagenes de mas de 16 MB. Bajar mas solo gasta ancho de
// banda para que el envio falle despues, en WhatsApp y no aca.
const MAX_BYTES = 16 * 1024 * 1024;

const TIMEOUT_MS = 15000;
const MAX_REDIRECCIONES = 3;

/**
 * Error caused by what the caller sent, not by the server.
 * The route turns .status into the HTTP code, so a bad URL is a 400 and not a
 * 500: from the panel's point of view nobody typed a wrong path.
 */
function errorDeCliente(mensaje) {
    const e = new Error(mensaje);
    e.status = 400;
    return e;
}

function mib(bytes) {
    return Math.round(bytes / 1048576 * 10) / 10;
}

/**
 * Baja una imagen y devuelve { buffer, contentType }.
 *
 * @param {string} url
 * @param {{maxBytes?: number, timeoutMs?: number, saltos?: number}} [opciones]
 * @returns {Promise<{buffer: Buffer, contentType: string}>}
 */
function descargar(url, opciones = {}) {
    const maxBytes = opciones.maxBytes ?? MAX_BYTES;
    const timeoutMs = opciones.timeoutMs ?? TIMEOUT_MS;
    const saltos = opciones.saltos ?? 0;

    let destino;
    try {
        destino = new URL(url);
    } catch {
        throw errorDeCliente('URL invalida: ' + url);
    }

    if (destino.protocol !== 'http:' && destino.protocol !== 'https:') {
        throw errorDeCliente(
            'La URL debe empezar con http:// o https:// (llegó: ' + destino.protocol + ')');
    }

    const transporte = destino.protocol === 'https:' ? https : http;

    return new Promise((resolve, reject) => {
        const peticion = transporte.get(destino, { timeout: timeoutMs }, (res) => {
            const status = res.statusCode || 0;

            // Las redirecciones se siguen a mano para poder ponerles un tope
            // explicito. Sin tope, dos paginas que se apuntan entre si dejan
            // la peticion dando vueltas hasta que se cae.
            if (status >= 300 && status < 400 && res.headers.location) {
                res.resume();
                if (saltos >= MAX_REDIRECCIONES) {
                    reject(errorDeCliente(
                        'Mas de ' + (MAX_REDIRECCIONES + 1) + ' redirecciones desde ' + url));
                    return;
                }
                let siguiente;
                try {
                    siguiente = new URL(res.headers.location, destino).href;
                } catch {
                    reject(errorDeCliente('Redireccion a una URL invalida: ' + res.headers.location));
                    return;
                }
                descargar(siguiente, { ...opciones, maxBytes, timeoutMs, saltos: saltos + 1 })
                    .then(resolve, reject);
                return;
            }

            if (status !== 200) {
                res.resume();
                reject(errorDeCliente('La URL respondio HTTP ' + status));
                return;
            }

            const tipo = String(res.headers['content-type'] || '').split(';')[0].trim();
            // Sin content-type no se objeta: hay servidores de imagenes que no
            // lo mandan. Si lo mandan y no es imagen, casi siempre es la pagina
            // de error del hotlinker, y mandarle eso a WhatsApp no aclara nada.
            if (tipo && !tipo.startsWith('image/')) {
                res.resume();
                reject(errorDeCliente('La URL no devolvio una imagen (Content-Type: ' + tipo + ')'));
                return;
            }

            const trozos = [];
            let total = 0;
            res.on('data', (trozo) => {
                total += trozo.length;
                if (total > maxBytes) {
                    res.destroy();
                    reject(errorDeCliente(
                        'La imagen supera el maximo de ' + mib(maxBytes) + ' MB'));
                    return;
                }
                trozos.push(trozo);
            });
            res.on('end', () => resolve({ buffer: Buffer.concat(trozos), contentType: tipo }));
            res.on('error', (e) => reject(errorDeCliente('Se corto la descarga: ' + e.message)));
        });

        peticion.on('timeout', () => {
            peticion.destroy();
            reject(errorDeCliente(
                'La URL tardo mas de ' + Math.round(timeoutMs / 1000) + 's'));
        });

        peticion.on('error', (e) => {
            reject(errorDeCliente('No se pudo bajar la URL: ' + e.message));
        });
    });
}

module.exports = { descargar, MAX_BYTES, errorDeCliente };