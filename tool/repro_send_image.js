/**
 * Reproduce el fallo de POST /send-image sin levantar Baileys.
 *
 * Levanta un express con EXACTAMENTE el mismo `limit` que declara server.js
 * (lo lee del archivo, no lo hardcodea: si alguien cambia server.js y no este
 * script, la prueba sigue diciendo la verdad).
 *
 * Uso:  node tool/repro_send_image.js
 */
const fs = require('fs');
const path = require('path');

const RAIZ = path.join(__dirname, '..');
const express = require(path.join(RAIZ, 'whatsapp_bot', 'node_modules', 'express'));
const SERVER_JS = path.join(RAIZ, 'whatsapp_bot', 'server.js');

// Leer el limite tal como quedo escrito en server.js.
const src = fs.readFileSync(SERVER_JS, 'utf8');
const m = src.match(/express\.json\(\{\s*limit:\s*'([^']+)'\s*\}\)/);
const limite = m ? m[1] : null;

console.log('=== Configuracion leida de whatsapp_bot/server.js ===');
console.log(
    limite
        ? `  express.json({ limit: '${limite}' })`
        : '  express.json()  SIN limit -> body-parser usa su default de 102400 bytes'
);
console.log('');

const app = express();
// Mismo middleware que server.js: con el limit declarado, o sin el si no hay.
app.use(express.json(limite ? { limit: limite } : undefined));

// Mismo contrato que server.js, pero sin Baileys: solo buffer y tamaño.
app.post('/send-image', (req, res) => {
    const { caption, imagePath, imageBase64 } = req.body;
    if (!imagePath && !imageBase64) {
        return res.status(400).json({ error: 'Se requiere "imagePath" o "imageBase64"' });
    }
    const buffer = Buffer.from(imageBase64, 'base64');
    res.json({ success: true, bytes_imagen: buffer.length, caption: caption || '' });
});

// El handler de errores que se agrego a server.js.
app.use((err, req, res, next) => {
    res.status(err.status || 500).json({ error: err.message || 'Error interno' });
});

const server = app.listen(0, async () => {
    const url = `http://127.0.0.1:${server.address().port}/send-image`;

    console.log('=== POST /send-image con imagenes de varios tamanos ===');
    console.log('');

    // JPEG minimo + relleno, para que se parezca a una foto.
    const jpegMinimo = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0xff, 0xd9];
    const rellenar = (bytes) => Buffer.concat([Buffer.from(jpegMinimo), Buffer.alloc(bytes, 0x41)]);

    const casos = [
        ['3 KB', 3 * 1024],
        ['50 KB', 50 * 1024],
        ['75 KB', 75 * 1024],
        ['150 KB', 150 * 1024],
        ['500 KB', 500 * 1024],
        ['2 MB', 2 * 1024 * 1024],
        ['8 MB', 8 * 1024 * 1024],
    ];

    let primerFallo = null;
    for (const [etiqueta, bytes] of casos) {
        const imagen = rellenar(bytes);
        const b64 = imagen.toString('base64');
        const cuerpo = JSON.stringify({ imageBase64: b64, caption: 'prueba' });
        let estado, detalle = '';
        try {
            const r = await fetch(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: cuerpo,
            });
            estado = r.status;
            const t = await r.text();
            detalle = t.length > 60 ? t.slice(0, 60) + '...' : t;
            if (r.status !== 200 && !primerFallo) primerFallo = { etiqueta, bytes: cuerpo.length };
        } catch (e) {
            estado = 'sin respuesta';
            detalle = e.message;
        }
        const marca = estado === 200 ? 'OK   ' : 'FALLA';
        console.log(
            `  ${marca} imagen ${etiqueta.padEnd(7)} -> JSON ${String(cuerpo.length).padStart(9)} bytes  HTTP ${String(estado).padEnd(4)} ${detalle}`
        );
    }

    console.log('');
    if (primerFallo) {
        console.log(`  Primer fallo: imagen de ${primerFallo.etiqueta} (JSON de ${primerFallo.bytes} bytes)`);
        console.log('  -> 25mb todavia no alcanza: hay que comprimir del lado del cliente.');
    } else {
        console.log('  Todas las imagenes probadas pasan.');
        console.log('  Cubre de sobra una foto de 16 MB en base64 (~21 MB), que es el');
        console.log('  maximo que acepta WhatsApp.');
    }

    // El caso que el panel manda: el parametro no es imagePath ni imageBase64.
    console.log('');
    console.log('=== Parametros: el panel manda "imageUrl", el servidor lee otros ===');
    for (const [etiqueta, cuerpo] of [
        ['imageUrl (lo que manda el panel)', { imageUrl: 'https://x/y.png', caption: 'c' }],
        ['imageBase64 (lo que manda Flutter)', { imageBase64: 'AAAA', caption: 'c' }],
    ]) {
        const r = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(cuerpo),
        });
        console.log(`  ${etiqueta.padEnd(34)} -> HTTP ${r.status}  ${await r.text()}`);
    }

    console.log('');
    console.log('Conclusion:');
    if (limite) {
        console.log(`  Con limit '${limite}' el 413 por body grande desaparece, y ademas`);
        console.log('  ahora responde JSON con el motivo en vez de una pagina HTML vacia.');
    } else {
        console.log('  Sin limit, body-parser corta en 102400 bytes de JSON, que en');
        console.log('  base64 son ~76 KB de imagen: casi cualquier foto o captura lo pasa.');
    }
    console.log('  El error salia de body-parser, antes del try/catch del endpoint,');
    console.log('  asi que el servidor no lo logueaba y la app solo veía un false.');

    server.close();
});