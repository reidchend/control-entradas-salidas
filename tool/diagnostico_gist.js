// Diagnostico del token de GitHub que publica la URL del tunel en el Gist.
//
// Por que existe: con un token vigente, el 401 "Bad credentials" casi nunca
// significa que el token este vencido. Significa que el valor que se manda no
// es el que uno cree, por una de estas razones:
//
//   1. La variable GITHUB_TOKEN del entorno de Windows tiene un valor viejo y
//      pisa lo que esta en el .env.
//   2. El .env tiene mas de una linea GITHUB_TOKEN y se usaba la primera.
//   3. El valor se guardo con el prefijo del encabezado ("token ghp_..."), y al
//      concatenarlo queda "token token ghp_...".
//   4. Un token fine-grained sin el permiso de Gists.
//
// Adivinar entre esas cuatro es peor que mirarlas, asi que este script las
// muestra todas y despues le pregunta a GitHub si el token sirve.
//
// No imprime el token: solo su largo y su prefijo.
//
// Uso:  node tool\diagnostico_gist.js

const https = require('https');
const {
  buscarTokenGithub,
  leerDelEnvFile,
  normalizarToken,
  prefijoDe,
  GIST_ID,
  ARCHIVO_API,
} = require('../whatsapp_bot/update_gist');

function pedir(opciones) {
  return new Promise((resolve) => {
    const req = https.request(opciones, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => {
        let json = null;
        try { json = JSON.parse(body); } catch { /* no es JSON */ }
        resolve({ status: res.statusCode, json, body });
      });
    });
    req.on('error', (e) => resolve({ status: 0, error: e.message }));
    if (opciones.payload) req.write(JSON.stringify(opciones.payload));
    req.end();
  });
}

function titulo(t) {
  console.log(`\n=== ${t} ===`);
}

async function main() {
  const token = buscarTokenGithub();

  titulo('1. De donde sale el token');

  const { envPath, encontradas } = leerDelEnvFile();
  const delEntorno = !!process.env.GITHUB_TOKEN;

  if (delEntorno) {
    console.log('Origen: variable de entorno GITHUB_TOKEN.');
    console.log('  OJO: esta pisa al archivo .env. Si el valor esta viejo,');
    console.log('        el token bueno del .env no se usa nunca.');
  } else if (encontradas.length === 0) {
    console.log('Origen: no encontrado.');
    console.log(`  No hay GITHUB_TOKEN en el entorno ni en ${envPath}`);
    return;
  } else if (encontradas.length === 1) {
    console.log(`Origen: ${envPath}, linea ${encontradas[0].linea}`);
  } else {
    console.log(`Origen: ${envPath}, linea ${encontradas[encontradas.length - 1].linea}`);
    console.log(`  OJO: el archivo tiene ${encontradas.length} lineas GITHUB_TOKEN.`);
    console.log('        Se usa la ultima. Las anteriores podrian estar viejas:');
    for (const e of encontradas) {
      console.log(`        linea ${e.linea}: ${e.token.length} caracteres`);
    }
  }

  titulo('2. Como se ve el valor (sin imprimirlo)');
  if (!token) {
    console.log('Token vacio.');
    return;
  }
  console.log(`Largo:            ${token.length} caracteres`);
  console.log(`Prefijo:          ${prefijoDe(token)}`);
  console.log(`Tiene espacios:   ${/\s/.test(token) ? 'SI  <-- no deberia' : 'no'}`);
  if (prefijoDe(token) === 'desconocido') {
    console.log('  OJO: no arranca con ghp_ ni github_pat_. Puede estar pegado');
    console.log('       con el prefijo del encabezado, o con texto de mas.');
  }

  titulo('3. Le pregunto a GitHub');
  const quien = await pedir({
    hostname: 'api.github.com',
    path: '/user',
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'lycoris-server',
    },
  });
  console.log(`GET /user  ->  ${quien.status}`);
  if (quien.status === 200) {
    console.log(`Autenticado como: ${quien.json && quien.json.login}`);
  } else if (quien.status === 401) {
    console.log('401: GitHub no reconoce este valor de token.');
    console.log('  O bien el token esta vencido o revocado de verdad, o bien');
    console.log('  el valor guardado no es el token (revisar el punto 2).');
  } else {
    console.log(`Cuerpo: ${(quien.body || '').slice(0, 300)}`);
  }

  titulo('4. Acceso al Gist');
  const gist = await pedir({
    hostname: 'api.github.com',
    path: `/gists/${GIST_ID}`,
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'lycoris-server',
    },
  });
  console.log(`GET /gists/${GIST_ID}  ->  ${gist.status}`);
  if (gist.status === 404) {
    console.log('404: el Gist no existe o el token no lo ve.');
  } else if (gist.status === 200 && gist.json) {
    console.log(`Archivos: ${Object.keys(gist.json.files || {}).join(', ') || '(ninguno)'}`);
    const contenido = gist.json.files && gist.json.files[ARCHIVO_API];
    if (contenido) console.log(`${ARCHIVO_API}: ${(contenido.content || '').trim()}`);
  }

  titulo('5. Prueba de escritura (no cambia el contenido)');
  const actual = gist.status === 200 && gist.json && gist.json.files
    && gist.json.files[ARCHIVO_API]
    ? gist.json.files[ARCHIVO_API].content
    : null;
  if (actual === null) {
    console.log(`No existe todavia ${ARCHIVO_API}; la prueba de escritura se`);
    console.log('hace sola en el primer arranque real del tunel.');
    return;
  }
  const escritura = await pedir({
    hostname: 'api.github.com',
    path: `/gists/${GIST_ID}`,
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
      'User-Agent': 'lycoris-server',
    },
    payload: { files: { [ARCHIVO_API]: { content: actual } } },
  });
  console.log(`PATCH (escribe lo mismo)  ->  ${escritura.status}`);
  if (escritura.status === 200) {
    console.log('Perfecto: el token puede publicar. El problema no es el permiso.');
  } else if (escritura.status === 401) {
    console.log('401: el token no autentica para escritura.');
  } else if (escritura.status === 403) {
    console.log('403: autentica pero no tiene permiso de escritura.');
    console.log('     Fine-grained: falta el permiso de cuenta "Gists: write".');
  } else {
    console.log(`Cuerpo: ${(escritura.body || '').slice(0, 300)}`);
  }
}

main();
