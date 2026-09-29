// Levanta el tunel de Cloudflare para la API de base de datos y publica la
// URL resultante en el Gist.
//
// Por que existe: las apps Windows y Android guardan solo el TOKEN. Si cada
// una guardara tambien la URL, un cambio de tunel obligaria a ir equipo por
// equipo. Publicando la URL en el Gist, lo unico que el usuario configura a
// mano es el token, que se puede rotar sin recompilar ni redistribuir.
//
// Modo por defecto: tunel rapido (trycloudflare.com). Su URL cambia en cada
// reinicio, y eso es justamente lo que el Gist resuelve: la app la torna sola.
// El tunel con nombre (--con-nombre) da una URL fija, pero exige un dominio en
// Cloudflare y una configuracion previa con `cloudflared tunnel login`.
//
// Uso:  node tool/iniciar_tunnel_api.js [--rapido | --con-nombre]
// Env:   CLOUDFLARED, API_LOCAL_PORT, GITHUB_TOKEN, GIST_ID, TUNNEL_NAME

const { spawn } = require('child_process');
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

// El rapido es el predeterminado a proposito: es el unico que no necesita
// cuenta ni dominio, asi que es lo que funciona en una instalacion nueva.
const rapido = !process.argv.includes('--con-nombre');

// Con el rapido, cada reinicio trae una URL nueva. Si cloudflared se cae y no
// vuelve solo, el Gist queda apuntando a una URL muerta y todas las apps
// dejan de conectar sin que nadie entienda por que. Se reintenta con
// espera creciente y un tope, para no ficar en un loop eterno si el problema
// es de configuracion y no de red.
const MAX_REINTENTOS = 10;
const ESPERA_BASE_MS = 5000;

const args = rapido
  ? ['tunnel', '--url', `http://localhost:${API_LOCAL_PORT}`]
  : ['tunnel', 'run', TUNNEL_NAME];

let intentos = 0;
let detenido = false;
let tunnel = null;
let publicado = false;
let ultimaSalida = '';

function delay(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function publicar(url) {
  if (publicado) return;
  publicado = true;
  console.log(`[TUNEL] URL de la API: ${url}`);
  if (rapido) {
    console.log('[TUNEL] Tunel rapido: la URL cambia en cada reinicio, y las');
    console.log('[TUNEL] apps la toman sola del Gist.');
  }
  updateApiUrl(url, { puerto: Number(API_LOCAL_PORT), rapido }).then((ok) => {
    if (ok) {
      console.log('[TUNEL] URL publicada. Las apps la van a leer al arrancar.');
    } else {
      console.error('[TUNEL] No se pudo publicar la URL. Hay que entrar la URL a mano.');
    }
  });
}

function alDetectar(chunk) {
  const salida = chunk.toString();
  ultimaSalida += salida;
  process.stdout.write(salida);
  // El rapido imprime la URL; el con nombre no, y hay que sacarla de
  // `cloudflared tunnel info`.
  const match = salida.match(/https:\/\/[a-zA-Z0-9.-]+\.(trycloudflare\.com|com|net|org|cl)/);
  if (match) publicar(match[0]);
}

// Tunel con nombre: la URL hay que sacarla del listado de Cloudflare.
async function buscarUrlConNombre() {
  return new Promise((resolve) => {
    const info = spawn(CLOUDFLARED, ['tunnel', 'info', TUNNEL_NAME],
      { stdio: ['ignore', 'pipe', 'pipe'] });
    let salida = '';
    info.stdout.on('data', (d) => (salida += d.toString()));
    info.stderr.on('data', (d) => (salida += d.toString()));
    info.on('close', () => {
      // Formato tipico: "Hostname: api.ejemplo.cl" o la URL en una columna.
      const fila = salida.split('\n').find((l) => /api\.|lycoris\./i.test(l));
      const match = fila && fila.match(/([a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+)/);
      if (match) {
        publicar(`https://${match[1]}`);
        resolve(true);
      } else {
        console.error('[TUNEL] No se pudo deducir la URL del tunel con nombre.');
        console.error('[TUNEL] Revisar: cloudflared tunnel info ' + TUNNEL_NAME);
        console.error('[TUNEL] y entrar la URL a mano en la app.');
        resolve(false);
      }
    });
  });
}

function explicarFallo() {
  if (rapido) return;
  // El mensaje de cloudflared dice que falta cert.pem, pero no dice que eso
  // es normal la primera vez ni que hay una salida sin cuenta de Cloudflare.
  if (!/origincert|cert\.pem/i.test(ultimaSalida)) return;
  console.error('');
  console.error('[TUNEL] El tunel con nombre necesita iniciar sesion en Cloudflare:');
  console.error('[TUNEL]   cloudflared tunnel login');
  console.error('[TUNEL]   cloudflared tunnel create control-entradas');
  console.error('[TUNEL] Para no depender de eso, usar el rapido (sin --con-nombre).');
}

async function arrancar() {
  intentos += 1;
  publicado = false;
  ultimaSalida = '';

  console.log(`[TUNEL] Iniciando ${rapido ? 'tunel rapido' : `tunel "${TUNNEL_NAME}"`} ` +
              `hacia http://localhost:${API_LOCAL_PORT}` +
              (intentos > 1 ? ` (intento ${intentos})` : ''));
  if (!rapido) console.log(`[TUNEL] Gist: ${GIST_ID}`);

  tunnel = spawn(CLOUDFLARED, args, { stdio: ['ignore', 'pipe', 'pipe'] });
  tunnel.stdout.on('data', alDetectar);
  tunnel.stderr.on('data', alDetectar);

  // Sin esto, si no se encuentra el binario Node tira un stack trace crudo y
  // el mensaje real (ENOENT) queda en la ultima linea.
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

  tunnel.on('close', async (code) => {
    explicarFallo();
    if (detenido) {
      console.log('[TUNEL] Detenido.');
      process.exit(code ?? 0);
    }

    if (intentos >= MAX_REINTENTOS) {
      console.error(`[TUNEL] El tunel cayo ${intentos} veces seguidas. Me detengo.`);
      console.error('[TUNEL] Mirar el log de la tarea: tool\\logs\\api.log');
      process.exit(code ?? 1);
    }

    const espera = Math.min(ESPERA_BASE_MS * intentos, 60000);
    console.log(`[TUNEL] Cloudflared terminó con código ${code}. Reintento en ${espera / 1000}s...`);
    await delay(espera);
    if (!detenido) arrancar();
  });

  if (!rapido) {
    // Con nombre la URL no sale del log, hay que consultarla. Se espera un
    // poco a que el tunel este listo.
    await delay(8000);
    if (!publicado && !detenido) buscarUrlConNombre();
  }
}

if (!process.env.GITHUB_TOKEN) {
  // No se aborta: el túnel tiene que levantar igual, así sea por una prueba.
  // Pero sin esto el Gist nunca se actualiza y las apps quedan apuntando a la
  // URL vieja, así que hay que dejarlo bien claro.
  console.warn('[TUNEL] AVISO: sin GITHUB_TOKEN el túnel levanta pero NO se');
  console.warn('[TUNEL] publica la URL. Las apps van a seguir usando la');
  console.warn('[TUNEL] anterior. Defini GITHUB_TOKEN en el entorno o en');
  console.warn('[TUNEL] whatsapp_bot\\.env');
}

arrancar();

for (const señal of ['SIGINT', 'SIGTERM']) {
  process.on(señal, () => {
    detenido = true;
    if (tunnel) tunnel.kill();
  });
}
