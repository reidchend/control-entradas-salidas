const https = require('https');

const GIST_ID = '5b37693a243d8d2235eea0647396b8d3';
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;

async function updateGist(url) {
  const data = JSON.stringify({ url });

  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'api.github.com',
      path: `/gists/${GIST_ID}`,
      method: 'PATCH',
      headers: {
        'Authorization': `token ${GITHUB_TOKEN}`,
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'User-Agent': 'whatsapp-bot'
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          console.log(`[GIST] URL updated: ${url}`);
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

    req.write(JSON.stringify({ files: { 'bot_url.json': { content: data } } }));
    req.end();
  });
}

module.exports = { updateGist };

if (require.main === module) {
  const url = process.argv[2];
  if (!url) {
    console.error('Usage: node update_gist.js <url>');
    process.exit(1);
  }
  updateGist(url).then(ok => process.exit(ok ? 0 : 1));
}
