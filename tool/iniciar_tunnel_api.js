// Levanta el tunel de Cloudflare para la API de base de datos y publica la
// URL resultante.
//
// Por que existe: las apps Windows y Android guardan solo el TOKEN. Si cada
// una guardara tambien la URL, un cambio de tunel obligaria a ir equipo por
// equipo. Publicando la URL en el Gist, el unico dato que se configura a mano
// es el token, que se puede rotar sin recompilar ni redistribuir.
//
// La URL del bot se publica aparte (bot_url.json): este tunel es con nombre y
// tiene URL estable, el del bot es rapido y cambia en cada reinicio.
//
// Uso:  node tool/iniciar_tunnel_api.js
// Env:   CLOUDFLARED, API_LOCAL_PORT, GITHUB_TOKEN, GIST_ID, TUNNEL_NAME

const { spawn, execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { updateApiUrl, GIST_ID } = require('../whatsapp_bot/update_gist');

// Busca cloudflared en este orden:
//   1. CLOUDFLARED del entorno (ruta explicita)
//   2. el .exe que usa el bot, si esta ahi
//   3. el PATH, que es donde lo deja winget
//
// Antes se usaba siempre (2) y si no existia el proceso moria con un stack
// trace de Node, sin decir que faltava instalar nada.
function resolverCloudflared() {
  if (process.env.CLOUDFLARED) return process.env.CLOUDFLARED;
  const enBot = path.join(__dirname, '..', 'whatsapp_bot', 'cloudflared.exe');
  if (fs.existsSync(enBot)) return enBot;
  if (fs.existsSync(path.join(__dirname, '..', 'whatsapp_bot', 'cloudflared'))) {
    return path.join(__dirname, '..', 'whatsapp_bot', 'cloudflared');
  }
  return 'cloudflared'; // que lo resuelva el PATH
}

const CLOUDFLARED = resolverCloudflared();
const API_LOCAL_PORT = process.env.API_LOCAL_PORT || '8501';
const TUNNEL_NAME = process.env.TUNNEL_NAME || 'control-entradas';

if (!process.env.GITHUB_TOKEN) {
  // No se aborta: el túnel tiene que levantar igual, así sea por una prueba.
  // Pero sin esto el Gist nunca se actualiza y las apps quedan apuntando a la
  // URL vieja, así que hay que dejarlo bien claro.
  console.warn('[TUNEL] AVISO: sin GITHUB_TOKEN el túnel levanta pero NO se');
  console.warn('[TUNEL] publica la URL. Las apps van a seguir usando la');
  console.warn('[TUNEL] anterior. Defini GITHUB_TOKEN en el entorno o en');
  console.warn('[TUNEL] whatsapp_bot\\.env');
}

if (!process.argv.includes('--rapido') && !TUNNEL_NAME) {
  console.error('[TUNNEL] Falta TUNNEL_NAME o el flag --rapido');
  process.exit(1);
}

// Con nombre: la URL no cambia entre reinicios, que es lo que necesitan las
// apps nativas. Sin nombre (`--rapido`) sirve para probar, pero la URL cambia
// cada vez y hay que volver a publicarla.
const rapido = process.argv.includes('--rapido');
const args = rapido
  ? ['tunnel', '--url', `http://localhost:${API_LOCAL_PORT}`]
  : ['tunnel', 'run', TUNNEL_NAME];

console.log(`[TUNEL] Iniciando ${rapido ? 'tunel rapido' : `tunel "${TUNNEL_NAME}"`} ` +
            `hacia http://localhost:${API_LOCAL_PORT}`);
if (!rapido) {
  console.log(`[TUNEL] Gist: ${GIST_ID}`);
}

let publicado = false;

function publicar(url) {
  if (publicado) return;
  publicado = true;
  console.log(`[TUNEL] URL de la API: ${url}`);
  if (rapido) {
    console.warn('[TUNEL] AVISO: tunel rapido. La URL cambia en cada reinicio;');
    console.warn('[TUNEL] las apps la van a retomar del Gist, pero conviene');
    console.warn('[TUNEL] usar un tunel con nombre para produccion.');
  }
  updateApiUrl(url, { puerto: Number(API_LOCAL_PORT), rapido }).then(ok => {
    if (ok) {
      console.log('[TUNEL] URL publicada. Las apps la van a leer al arrancar.');
    } else {
      console.error('[TUNEL] No se pudo publicar la URL. Hay que entrar la URL a mano.');
    }
  });
}

const tunnel = spawn(CLOUDFLARED, args, { stdio: ['ignore', 'pipe', 'pipe'] });

// Sin esto, si no se encuentra el binario Node tira un stack trace crudo y el
// mensaje real (ENOENT) queda en la ultima linea.
tunnel.on('error', (err) => {
  if (err.code === 'ENOENT') {
    console.error(`[TUNEL] No se encontro cloudflared (probei: ${CLOUDFLARED}).`);
    console.error('[TUNEL] Instalalo con:  winget install --id Cloudflare.cloudflared');
    console.error('[TUNEL] O decile donde esta con:  $env:CLOUDFLARED="C:\\ruta\\cloudflared.exe"');
  } else {
    console.error(`[TUNEL] No se pudo lanzar cloudflared: ${err.message}`);
  }
  process.exit(1);
});

let ultimaSalida = '';

function alDetectar(chunk) {
  const salida = chunk.toString();
  ultimaSalida += salida;
  process.stdout.write(salida);
  // Con tunnel con nombre Cloudflare no imprime la URL: hay que leerla de
  // `cloudflared tunnel info`, así que se consulta una vez.
  const match = salida.match(/https:\/\/[a-zA-Z0-9.-]+\.(trycloudflare\.com|com|net|org|cl)/);
  if (match) publicar(match[0]);
}

tunnel.stdout.on('data', alDetectar);
tunnel.stderr.on('data', alDetectar);

// Tunel con nombre: la URL hay que sacarla del listado de Cloudflare.
if (!rapido) {
  setTimeout(() => {
    if (publicado) return;
    const info = spawn(CLOUDFLARED, ['tunnel', 'info', TUNNEL_NAME],
      { stdio: ['ignore', 'pipe', 'pipe'] });
    let salida = '';
    info.stdout.on('data', d => salida += d.toString());
    info.stderr.on('data', d => salida += d.toString());
    info.on('close', () => {
      if (publicado) return;
      // Formato tipico: "Hostname: api.ejemplo.cl" o la URL en una columna.
      const fila = salida.split('\n').find(l => /api\.|lycoris\./i.test(l));
      const match = fila && fila.match(/([a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+)/);
      if (match) publicar(`https://${match[1]}`);
      else {
        console.error('[TUNEL] No se pudo deducir la URL del tunel con nombre.');
        console.error('[TUNEL] Revisar: cloudflared tunnel info ' + TUNNEL_NAME);
        console.error('[TUNEL] y entrar la URL a mano en la app.');
      }
    });
  }, 8000);
}

tunnel.on('close', (code) => {
  // El mensaje de cloudflared dice que falta cert.pem, pero no dice que eso
  // es normal la primera vez y que hay dos caminos. El de `--rapido` no
  // necesita cuenta de Cloudflare y es el que conviene para empezar.
  if (!rapido && /origincert|cert\.pem/i.test(ultimaSalida)) {
    console.error('');
    console.error('[TUNEL] El tunel con nombre necesita iniciar sesion en Cloudflare.');
    console.error('[TUNEL] Para empezar ya, usar el rapido:');
    console.error('[TUNEL]   tool\\iniciar_api.bat --rapido');
    console.error('[TUNEL] Para dejarlo bien (URL estable), una sola vez:');
    console.error('[TUNEL]   cloudflared tunnel login');
    console.error('[TUNEL]   cloudflared tunnel create control-entradas');
  }
  console.log(`[TUNEL] Cloudflared terminó con código ${code}`);
  process.exit(code ?? 0);
});

process.on('SIGINT', () => tunnel.kill());
process.on('SIGTERM', () => tunnel.kill());
