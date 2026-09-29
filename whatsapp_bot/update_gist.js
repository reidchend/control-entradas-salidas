const https = require('https');

const GIST_ID = process.env.GIST_ID || '5b37693a243d8d2235eea0647396b8d3';
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;

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

module.exports = { updateGist, updateBotUrl, updateApiUrl, GIST_ID, ARCHIVO_API, ARCHIVO_BOT };

if (require.main === module) {
  const url = process.argv[2];
  if (!url) {
    console.error('Usage: node update_gist.js <url> [archivo]');
    process.exit(1);
  }
  const archivo = process.argv[3] || ARCHIVO_BOT;
  updateGist(archivo, { url }).then(ok => process.exit(ok ? 0 : 1));
}
