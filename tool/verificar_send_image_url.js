/*
 * Verifica que /send-image acepte "imageUrl", que es lo que manda el panel web.
 *
 * El bug era un desajuste de nombres: el panel mandaba {imageUrl, caption} y el
 * servidor solo desestructuraba {caption, imagePath, imageBase64}, asi que
 * imageUrl se perdia y la respuesta era siempre 400. Como el nombre del campo
 * no coincide en ningun lado, probar el endpoint contra el bot vivo no alcanza:
 * hay que mirar que el buffer que llega a sendImageToGroup es el de la URL.
 *
 * Por eso la prueba no toca el bot real. Levanta una copia LITERAL de
 * server.js y descargar_imagen.js en un directorio temporal, con un bot.js de
 * mentira que solo anota lo que le pasarían. Si se rompe algo, es el codigo de
 * la copia, que es el deCommit, no una reimplementacion.
 *
 * Lo que corre:
 *   A. unitarios de descargar_imagen.js contra un servidor de prueba local
 *   B. extremo a extremo contra la copia de server.js con el bot stub
 *
 * Uso: node tool/verificar_send_image_url.js
 */
const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');

const RAIZ = path.resolve(__dirname, '..');
const BOT = path.join(RAIZ, 'whatsapp_bot');
const TEMP = path.join(BOT, '.tmp_verificar_send_image');

// 1x1 transparente valido. No hace falta que sea lindo: la prueba compara los
// bytes que llegan a sendImageToGroup contra los que sirvio el servidor.
const PNG_1x1 = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kg' +
    'AAAABJRU5ErkJggg==',
    'base64'
);

let fallos = 0;

function check(etiqueta, condicion, detalle) {
    if (condicion) {
        console.log('  OK    ' + etiqueta);
    } else {
        console.log('  FALLA ' + etiqueta);
        if (detalle !== undefined && detalle !== '') {
            console.log('         ' + String(detalle).split('\n').join('\n         '));
        }
        fallos++;
    }
}

function sha(buf) {
    return crypto.createHash('sha256').update(buf).digest('hex');
}

function puertoLibre() {
    // Bind y release: hay una carrera minima contra otro proceso, pero en esta
    // maquina alcanza y evita hardcodear un puerto que puede estar ocupado.
    return new Promise((resolve) => {
        const srv = http.createServer();
        srv.listen(0, '127.0.0.1', () => {
            const p = srv.address().port;
            srv.close(() => resolve(p));
        });
    });
}

// ---------------------------------------------------------------- fixtures

function crearFixture() {
    return http.createServer((req, res) => {
        const ruta = req.url.split('?')[0];
        if (ruta === '/png') {
            res.writeHead(200, { 'Content-Type': 'image/png' });
            res.end(PNG_1x1);
        } else if (ruta === '/jpg') {
            res.writeHead(200, { 'Content-Type': 'image/jpeg; charset=binary' });
            res.end(PNG_1x1);
        } else if (ruta === '/rota') {
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            res.end('no existe');
        } else if (ruta === '/html') {
            res.writeHead(200, { 'Content-Type': 'text/html' });
            res.end('<html><body>pagina de error del hotlinker</body></html>');
        } else if (ruta === '/rota-tipo') {
            res.writeHead(500, { 'Content-Type': 'text/plain' });
            res.end('se rompio');
        } else if (ruta === '/redirige') {
            res.writeHead(302, { Location: '/png' });
            res.end();
        } else if (ruta === '/bucle') {
            res.writeHead(302, { Location: '/bucle' });
            res.end();
        } else if (ruta === '/colgado') {
            // No responde nunca: para el timeout.
        } else if (ruta === '/pesada') {
            // 17 MB: supera el maximo de 16 MB del limite de WhatsApp.
            res.writeHead(200, { 'Content-Type': 'image/png' });
            const bloque = Buffer.alloc(64 * 1024, 7);
            let enviado = 0;
            const total = 17 * 1024 * 1024;
            const bombear = () => {
                while (enviado < total) {
                    enviado += bloque.length;
                    if (!res.write(bloque)) {
                        res.once('drain', bombear);
                        return;
                    }
                }
                res.end();
            };
            bombear();
        } else {
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            res.end('ruta desconocida');
        }
    });
}

// ------------------------------------------------ A. unitarios del helper

async function unitarios(base) {
    console.log('=== A. descargar_imagen.js contra un servidor local ===');
    const { descargar, MAX_BYTES } = require(path.join(BOT, 'descargar_imagen.js'));

    const t = await descargar(base + '/png');
    check('baja una imagen y devuelve los bytes intactos',
        sha(t.buffer) === sha(PNG_1x1) && t.contentType === 'image/png',
        'contentType=' + t.contentType + ' bytes=' + t.buffer.length);

    const j = await descargar(base + '/jpg');
    check('tolera parametros en el content-type (image/jpeg; charset=binary)',
        j.contentType === 'image/jpeg' && sha(j.buffer) === sha(PNG_1x1),
        'contentType=' + j.contentType);

    const r = await descargar(base + '/redirige');
    check('sigue una redireccion', sha(r.buffer) === sha(PNG_1x1));

    // Errores: cada uno con .status 400, para que la ruta responda 400 y no 500.
    const esperando = [
        ['404', '/rota', 'HTTP 404', /HTTP 404/],
        ['500', '/rota-tipo', 'HTTP 500', /HTTP 500/],
        ['html en vez de imagen', '/html', 'no devolvio una imagen', /no devolvio una imagen/],
        ['bucle de redirecciones', '/bucle', 'redirecciones', /redirecciones/],
    ];
    for (const [nombre, ruta, contiene, re] of esperando) {
        let err = null;
        try {
            await descargar(base + ruta);
        } catch (e) {
            err = e;
        }
        check('falla con "' + contiene + '" (' + nombre + ')',
            err !== null && re.test(err.message), err ? err.message : '(no fallo)');
        check('  y el error viene marcado como 400', err !== null && err.status === 400,
            err ? 'status=' + err.status : '(no fallo)');
    }

    // Protocolo y formato: fallan antes de abrir un socket.
    for (const [nombre, url, re] of [
        ['ftp://', 'ftp://ejemplo.com/a.png', /http:\/\/ o https:\/\//],
        ['una cadena cualquiera', 'no es una url', /URL invalida/],
    ]) {
        let err = null;
        try {
            await descargar(url);
        } catch (e) {
            err = e;
        }
        check('rechaza ' + nombre, err !== null && re.test(err.message),
            err ? err.message : '(no fallo)');
    }

    // Timeout: el fixture /colgado nunca responde.
    let err = null;
    let t0 = Date.now();
    try {
        await descargar(base + '/colgado', { timeoutMs: 700 });
    } catch (e) {
        err = e;
    }
    check('corta la descarga colgada y no se queda esperando',
        err !== null && /tardo mas de/.test(err.message) && Date.now() - t0 < 5000,
        err ? err.message + ' (' + (Date.now() - t0) + 'ms)' : '(no fallo)');

    // Peso: se corta en caliente, no baja los 17 MB de una.
    err = null;
    t0 = Date.now();
    try {
        await descargar(base + '/pesada', { maxBytes: 64 * 1024, timeoutMs: 10000 });
    } catch (e) {
        err = e;
    }
    check('corta en caliente al pasarse del maximo',
        err !== null && /supera el maximo/.test(err.message),
        err ? err.message : '(no fallo)');

    check('el maximo por defecto es el de WhatsApp (16 MB)', MAX_BYTES === 16 * 1024 * 1024,
        'MAX_BYTES=' + MAX_BYTES);
    console.log('');
}

// ------------------------------------------------ B. extremo a extremo

const STUB_BOT = `// Stub del bot: no se conecta a WhatsApp y no manda nada al grupo.
// Solo anota lo que le habria llegado, que es lo que hay que verificar.
const crypto = require('crypto');
const registros = [];
module.exports = {
    registros,
    isConnected: () => true,
    connect: async () => {},
    getCurrentQR: () => null,
    getGroupId: () => '120000000000000000@g.us',
    setGroupId: () => {},
    getReportGroupId: () => null,
    setReportGroupId: () => {},
    getGroups: async () => [],
    getGroupMetadata: async () => ({ subject: 'grupo de prueba' }),
    sendToGroup: async () => {},
    sendMessage: async () => {},
    sendImageToGroup: async (buffer, caption) => {
        registros.push({
            bytes: buffer.length,
            sha: crypto.createHash('sha256').update(buffer).digest('hex'),
            caption: caption
        });
        return true;
    },
    sendReportToGroup: async () => {},
    sendDocumentToGroup: async () => {}
};
`;

const HIJO = `// Corre los escenarios HTTP contra la copia de server.js y tira el resultado.
const http = require('http');
const base = process.argv[2];
const fixture = process.argv[3];
const token = 'token-de-prueba-123';
const salida = [];

process.env.PORT = base;
process.env.WHATSAPP_BOT_TOKEN = token;
const bot = require('./bot');
require('./server.js');

function pedir(opcion, cuerpo, conToken) {
    return new Promise((resolve) => {
        const datos = JSON.stringify(cuerpo);
        const peticion = http.request({
            host: '127.0.0.1',
            port: Number(base),
            path: opcion,
            method: 'POST',
            headers: Object.assign(
                { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(datos) },
                conToken ? { 'x-auth-token': token } : {}
            )
        }, (res) => {
            let texto = '';
            res.on('data', (t) => (texto += t));
            res.on('end', () => {
                let cuerpo2 = null;
                try { cuerpo2 = JSON.parse(texto); } catch (e) { cuerpo2 = texto; }
                resolve({ status: res.statusCode, body: cuerpo2 });
            });
        });
        peticion.on('error', (e) => resolve({ status: 0, body: { error: e.code || e.message } }));
        peticion.end(datos);
    });
}

async function esperarArranque() {
    for (let i = 0; i < 60; i++) {
        const r = await pedir('/send-image', {}, true);
        if (r.status !== 0) return true;
        await new Promise((r2) => setTimeout(r2, 100));
    }
    return false;
}

(async () => {
    const arrancó = await esperarArranque();

    // El bug: el panel manda imageUrl. Antes esto era 400 "Se requiere
    // imagePath o imageBase64" sin mirar el valor.
    salida.push({
        nombre: 'imageUrl de una imagen real',
        r: await pedir('/send-image', { imageUrl: fixture + '/png', caption: 'desde el panel' }, true)
    });
    salida.push({ nombre: 'registro tras imageUrl', registros: bot.registros.slice() });

    salida.push({ nombre: 'imageUrl que da 404',
        r: await pedir('/send-image', { imageUrl: fixture + '/rota' }, true) });
    salida.push({ nombre: 'imageUrl que devuelve html',
        r: await pedir('/send-image', { imageUrl: fixture + '/html' }, true) });
    salida.push({ nombre: 'imageUrl ftp', r: await pedir('/send-image', { imageUrl: 'ftp://x/a.png' }, true) });
    salida.push({ nombre: 'imageUrl de 17 MB',
        r: await pedir('/send-image', { imageUrl: fixture + '/pesada' }, true) });

    // Regresion: los dos caminos que ya funcionaban tienen que seguir andando.
    salida.push({ nombre: 'imageBase64 (la app Flutter)',
        r: await pedir('/send-image',
            { imageBase64: require('fs').readFileSync(require('path').join(__dirname, 'fixture.png')).toString('base64'),
              caption: 'desde la app' }, true) });
    salida.push({ nombre: 'imagePath (a mano)',
        r: await pedir('/send-image',
            { imagePath: require('path').join(__dirname, 'fixture.png'), caption: 'ruta local' }, true) });

    salida.push({ nombre: 'sin ningun campo',
        r: await pedir('/send-image', { caption: 'nada' }, true) });
    salida.push({ nombre: 'sin token', r: await pedir('/send-image', { imageUrl: fixture + '/png' }, false) });

    salida.push({ nombre: 'registro final', registros: bot.registros.slice() });

    console.log('RESULTADOS_JSON=' + JSON.stringify({ arrancó, salida }));
    process.exit(0);
})();
`;

function extremoAExtremo(fixtureBase) {
    return (async function () {
    console.log('=== B. /send-image contra una copia literal de server.js ===');

    fs.rmSync(TEMP, { recursive: true, force: true });
    fs.mkdirSync(TEMP, { recursive: true });
    // Copias literales: si el codigo cambia, la prueba cambia con el.
    fs.copyFileSync(path.join(BOT, 'server.js'), path.join(TEMP, 'server.js'));
    fs.copyFileSync(path.join(BOT, 'descargar_imagen.js'), path.join(TEMP, 'descargar_imagen.js'));
    fs.copyFileSync(path.join(BOT, 'panel_bot.html'), path.join(TEMP, 'panel_bot.html'));
    fs.writeFileSync(path.join(TEMP, 'bot.js'), STUB_BOT, 'utf8');
    fs.writeFileSync(path.join(TEMP, 'hijo.js'), HIJO, 'utf8');
    fs.writeFileSync(path.join(TEMP, 'fixture.png'), PNG_1x1);

    const puerto = await puertoLibre();
    // spawn y NO spawnSync: el servidor de prueba vive en este proceso, asi que
    // el event loop tiene que seguir libre para poder responderle al hijo. Con
    // spawnSync el padre queda bloqueado, el fixture nunca contesta y todas las
    // descargas mueren por timeout: la prueba pasa por un bug del arnes.
    const p = await new Promise((resolve) => {
        const hijo = spawn(process.execPath, ['hijo.js', String(puerto), fixtureBase], {
            cwd: TEMP,
            stdio: ['ignore', 'pipe', 'pipe'],
        });
        const trozos = { out: [], err: [] };
        hijo.stdout.on('data', (d) => trozos.out.push(d));
        hijo.stderr.on('data', (d) => trozos.err.push(d));
        const reloj = setTimeout(() => hijo.kill(), 120000);
        hijo.on('error', (e) => {
            clearTimeout(reloj);
            resolve({ error: e, stdout: '', stderr: '' });
        });
        hijo.on('close', () => {
            clearTimeout(reloj);
            resolve({
                error: null,
                stdout: Buffer.concat(trozos.out).toString('utf8'),
                stderr: Buffer.concat(trozos.err).toString('utf8'),
            });
        });
    });

    if (p.error) {
        check('el hijo arranca', false, String(p.error));
        console.log('');
        return;
    }

    const linea = (p.stdout || '').split('\n').find((l) => l.startsWith('RESULTADOS_JSON='));
    if (!linea) {
        check('el hijo termina y reporta', false,
            'stdout:\n' + (p.stdout || '') + '\nstderr:\n' + (p.stderr || ''));
        console.log('');
        return;
    }

    const { arrancó, salida } = JSON.parse(linea.slice('RESULTADOS_JSON='.length));
    check('la copia de server.js levanta y escucha', arrancó === true);
    if (!arrancó) {
        console.log('');
        return;
    }

    const porNombre = {};
    for (const s of salida) porNombre[s.nombre] = s;

    // --- el bug arreglado
    const ok = porNombre['imageUrl de una imagen real'];
    check('imageUrl devuelve 200 (antes era 400 siempre)',
        ok.r.status === 200 && ok.r.body && ok.r.body.success === true,
        'status=' + ok.r.status + ' body=' + JSON.stringify(ok.r.body));

    const reg1 = porNombre['registro tras imageUrl'].registros;
    check('llego UN envio al bot, no ninguno ni dos',
        reg1.length === 1, 'registros=' + reg1.length);
    check('los bytes que llegaron son los de la URL, no otros',
        reg1.length === 1 && reg1[0].sha === sha(PNG_1x1),
        reg1.length ? 'sha=' + reg1[0].sha + ' esperado=' + sha(PNG_1x1) : '(sin registros)');
    check('llego el caption del panel',
        reg1.length === 1 && reg1[0].caption === 'desde el panel',
        reg1.length ? 'caption=' + JSON.stringify(reg1[0].caption) : '(sin registros)');
    check('los ultimos 4 bytes son los de un PNG',
        reg1.length === 1 && reg1[0].bytes === PNG_1x1.length,
        reg1.length ? reg1[0].bytes + ' vs ' + PNG_1x1.length : '');

    // --- errores: 400 con el motivo, no 500 ni el "falta un campo"
    const errores = [
        ['imageUrl que da 404', /HTTP 404/],
        ['imageUrl que devuelve html', /no devolvio una imagen/],
        ['imageUrl ftp', /http:\/\/ o https:\/\//],
        ['imageUrl de 17 MB', /supera el maximo/],
    ];
    for (const [nombre, re] of errores) {
        const r = porNombre[nombre].r;
        const msg = (r.body && r.body.error) || JSON.stringify(r.body);
        check(nombre + ' -> 400 con el motivo',
            r.status === 400 && re.test(msg), 'status=' + r.status + ' error=' + msg);
        check('  y no es el error de "falta un campo"', !/Se requiere/.test(msg), msg);
    }

    // --- regresion de los caminos que ya andaban
    const b64 = porNombre['imageBase64 (la app Flutter)'].r;
    check('imageBase64 sigue funcionando (la app Flutter no se rompe)',
        b64.status === 200 && b64.body && b64.body.success === true,
        'status=' + b64.status + ' body=' + JSON.stringify(b64.body));

    const ruta = porNombre['imagePath (a mano)'].r;
    check('imagePath sigue funcionando',
        ruta.status === 200 && ruta.body && ruta.body.success === true,
        'status=' + ruta.status + ' body=' + JSON.stringify(ruta.body));

    const final = porNombre['registro final'].registros;
    check('los tres caminos de imagen enviaron una imagen cada uno',
        final.length === 3, 'registros=' + final.length);
    check('y las tres imagenes son identicas byte a byte (no se corrompio ninguna)',
        final.length === 3 && final.every((r) => r.sha === sha(PNG_1x1)));

    // --- validacion de entrada
    const vacio = porNombre['sin ningun campo'].r;
    check('sin ningun campo sigue dando 400',
        vacio.status === 400 && /Se requiere/.test(vacio.body.error || ''),
        'status=' + vacio.status + ' error=' + (vacio.body && vacio.body.error));
    check('  y ahora el mensaje nombra los tres campos, no dos',
        /imageUrl/.test(vacio.body.error || '') && /imagePath/.test(vacio.body.error || '')
        && /imageBase64/.test(vacio.body.error || ''),
        vacio.body && vacio.body.error);

    const sinToken = porNombre['sin token'].r;
    check('sin token sigue dando 401 (no se abrio una puerta)',
        sinToken.status === 401, 'status=' + sinToken.status);

    fs.rmSync(TEMP, { recursive: true, force: true });
    console.log('');
    })();
}

(async function main() {
    console.log('=== Archivos bajo prueba (copiados tal cual, no reimplementados) ===');
    for (const f of ['server.js', 'descargar_imagen.js', 'panel_bot.html']) {
        console.log('  whatsapp_bot/' + f + '  ' + fs.statSync(path.join(BOT, f)).size + ' bytes');
    }
    console.log('');

    const fixture = crearFixture();
    await new Promise((r) => fixture.listen(0, '127.0.0.1', r));
    const base = 'http://127.0.0.1:' + fixture.address().port;

    try {
        await unitarios(base);
        await extremoAExtremo(base);
    } finally {
        fixture.close();
        fs.rmSync(TEMP, { recursive: true, force: true });
    }

    if (fallos === 0) {
        console.log('Todo OK: /send-image acepta imageUrl y los otros dos caminos siguen igual');
    } else {
        console.log('FALLARON ' + fallos + ' verificaciones');
    }
    process.exit(fallos ? 1 : 0);
})();