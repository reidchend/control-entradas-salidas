const { spawn, exec } = require('child_process');
const { updateBotUrl } = require('./update_url');

const CLOUDFLARED = process.env.CLOUDFLARED || require('path').join(__dirname, 'cloudflared.exe');
const LOCAL_PORT = process.env.LOCAL_PORT || '3000';

let urlFound = false;

function openBrowser(url) {
  const cmd = process.platform === 'win32' ? 'start' : 'xdg-open';
  exec(`${cmd} "${url}"`);
  console.log(`[TUNNEL] Opening browser: ${url}`);
}

function handleUrl(url) {
  if (urlFound) return;
  urlFound = true;
  console.log(`\n[TUNNEL] URL detected: ${url}`);
  updateBotUrl(url).then(ok => {
    if (ok) console.log('[TUNNEL] URL saved to Supabase');
  });
  openBrowser(url);
}

const tunnel = spawn(CLOUDFLARED, ['tunnel', '--url', `http://localhost:${LOCAL_PORT}`], {
  stdio: ['ignore', 'pipe', 'pipe']
});

tunnel.stdout.on('data', (data) => {
  const output = data.toString();
  console.log(output);
  const match = output.match(/https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com/);
  if (match) handleUrl(match[0]);
});

tunnel.stderr.on('data', (data) => {
  const output = data.toString();
  console.log(output);
  const match = output.match(/https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com/);
  if (match) handleUrl(match[0]);
});

tunnel.on('close', (code) => {
  console.log(`[TUNNEL] Cloudflared exited with code ${code}`);
  process.exit(code);
});

process.on('SIGINT', () => tunnel.kill());
process.on('SIGTERM', () => tunnel.kill());
