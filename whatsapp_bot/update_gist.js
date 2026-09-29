const https = require('https');
const fs = require('fs');
const path = require('path');

const GIST_ID = process.env.GIST_ID || '5b37693a243d8d2235eea0647396b8d3';

// Prefijos reales de los tokens de GitHub. Sirven para detectar que se mando
// otra cosa (por ejemplo, el valor completo del encabezado) sin tener que
// imprimir el token.
const PREFIJOS = ['ghp_', 'gho_', 'ghu_', 'ghs_', 'ghr_', 'github_pat_'];

/**
 * Limpia el valor leido del `.env` o del entorno.
 *
 * El 401 "Bad credentials" con un token que sigue vigente casi siempre es esto:
 * el valor guardado ya venia con el prefijo del encabezado ("token ghp_..." o
 * "Bearer ghp_..."), y al concatenarlo el encabezado quedaba
 * "token token ghp_...". Tambien aparecen comillas o espacios al final cuando
 * el archivo se edito a mano o|Windows dejo un CR pegado.
 *
 * @param {string} bruto valor tal cual estaba guardado
 * @returns {string} token listo para mandar
 */
function normalizarToken(bruto) {
  let t = String(bruto == null ? '' : bruto).trim();
  t = t.replace(/^(token|bearer)\s+/i, '');
  t = t.replace(/^["']|["']$/g, '');
  return t.trim();
}

function prefijoDe(t) {
  return PREFIJOS.find((p) => t.startsWith(p)) || 'desconocido';
}

/**
 * Lee las lineas GITHUB_TOKEN del `.env` del bot, todas.
 *
 * @returns {{envPath: string, encontradas: Array<{linea: number, bruto: string, token: string}>}}
 */
function leerDelEnvFile() {
  const envPath = path.join(__dirname, '.env');
  if (!fs.existsSync(envPath)) return { envPath, encontradas: [] };

  const encontradas = [];
  fs.readFileSync(envPath, 'utf8')
    .split(/\r?\n/)
    .forEach((linea, i) => {
      // Solo cuenta lineas sin comentario: un ejemplo anotado con # al final
      // del archivo no debe pisar el token real.
      const m = linea.match(/^\s*GITHUB_TOKEN\s*=\s*(.*?)\s*$/);
      if (m) encontradas.push({ linea: i + 1, bruto: m[1], token: normalizarToken(m[1]) });
    });

  return { envPath, encontradas };
}

// El token se busca en el entorno y, si no esta, en el .env del bot. Esto
// importa para mas que la prueba manual: la tarea de autoarranque lanza el
// proceso sin variables de entorno, y sin esto publicaria "token undefined".
// Es el mismo .env que ya usa iniciar_bot.bat.
function buscarTokenGithub() {
  if (process.env.GITHUB_TOKEN) return normalizarToken(process.env.GITHUB_TOKEN);
  const { encontradas } = leerDelEnvFile();
  // Si hay mas de una, gana la ultima: es la que se agrego al final cuando se
  // renovó el token. Antes ganaba la primera, asi que un token viejo al
  // principio del archivo dejaba usando el viejo para siempre.
  return encontradas.length ? encontradas[encontradas.length - 1].token : undefined;
}

const GITHUB_TOKEN = buscarTokenGithub();

// Archivos que publica el bot, separados porque cada uno se actualiza por su
// cuenta: el túnel del bot cambia al reiniciar y no debe pisar la URL de la
// API, que viene del túnel con nombre.
const ARCHIVO_BOT = 'bot_url.json';
const ARCHIVO_API = 'api_url.json';

/**
 * Escribe un archivo JSON dentro del Gist.
 *
 * @param {string} archivo nombre del archivo dentro del Gist
 * @param {object} contenido objeto a serializar
 * @returns {Promise<boolean>} true si GitHub confirmó la escritura
 */
function updateGist(archivo, contenido) {
  const data = JSON.stringify(contenido);

  // Fallar aca es mejor que mandar `token undefined`: la respuesta de GitHub
  // en ese caso es 401 y el mensaje real queda buried en un body de error.
  if (!GITHUB_TOKEN) {
    console.error(
      `[GIST] Falta GITHUB_TOKEN. Definilo en el entorno o en ${path.join(__dirname, '.env')}`
    );
    return Promise.resolve(false);
  }

  return new Promise((resolve) => {
    const req = https.request({
      hostname: 'api.github.com',
      path: `/gists/${GIST_ID}`,
      method: 'PATCH',
      headers: {
        'Authorization': `token ${GITHUB_TOKEN}`,
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'User-Agent': 'lycoris-server'
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          console.log(`[GIST] ${archivo} actualizado: ${data}`);
          resolve(true);
        } else if (res.statusCode === 401 || res.statusCode === 403) {
          // El body crudo de GitHub ("Bad credentials") no orienta nada. Lo
          // mas comun es un token vencido o revocado, que es justo lo que no
          // se nota hasta que las apps dejan de encontrar la URL.
          console.error(`[GIST] Error ${res.statusCode}: el GITHUB_TOKEN no sirve.`);
          console.error('[GIST] Suele ser token vencido, o mal copiado, o con el');
          console.error('[GIST] prefijo "token " pegado, o sin permiso de escritura');
          console.error('[GIST] sobre Gists (classic "gist" o fine-grained');
          console.error('[GIST] "Gists: write"). Para ver cual es:');
          console.error('[GIST]   node tool\\diagnostico_gist.js');
          resolve(false);
        } else {
          console.error(`[GIST] Error ${res.statusCode}: ${body}`);
          resolve(false);
        }
      });
    });

    req.on('error', (e) => {
      console.error(`[GIST] Request error: ${e.message}`);
      resolve(false);
    });

    req.write(JSON.stringify({ files: { [archivo]: { content: data } } }));
    req.end();
  });
}

const updateBotUrl = (url) => updateGist(ARCHIVO_BOT, { url });
const updateApiUrl = (url, extra = {}) =>
  updateGist(ARCHIVO_API, { url, actualizado: new Date().toISOString(), ...extra });

module.exports = {
  updateGist, updateBotUrl, updateApiUrl,
  buscarTokenGithub, leerDelEnvFile, normalizarToken, prefijoDe,
  GIST_ID, ARCHIVO_API, ARCHIVO_BOT,
};

if (require.main === module) {
  const url = process.argv[2];
  if (!url) {
    console.error('Usage: node update_gist.js <url> [archivo]');
    process.exit(1);
  }
  const archivo = process.argv[3] || ARCHIVO_BOT;
  updateGist(archivo, { url }).then(ok => process.exit(ok ? 0 : 1));
}
