const { spawn } = require('child_process');
const { updateBotUrl } = require('./update_url');

const CLOUDFLARED = process.env.CLOUDFLARED || 'cloudflared.exe';
const LOCAL_PORT = process.env.LOCAL_PORT || '3000';

let urlFound = false;

const tunnel = spawn(CLOUDFLARED, ['tunnel', '--url', `http://localhost:${LOCAL_PORT}`], {
  stdio: ['ignore', 'pipe', 'pipe']
});

tunnel.stdout.on('data', (data) => {
  const output = data.toString();
  console.log(output);

  if (!urlFound) {
    const match = output.match(/https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com/);
    if (match) {
      urlFound = true;
      const url = match[0];
      console.log(`\n[TUNNEL] URL detected: ${url}`);
      updateBotUrl(url).then(ok => {
        if (ok) console.log('[TUNNEL] URL saved to Supabase');
      });
    }
  }
});

tunnel.stderr.on('data', (data) => {
  const output = data.toString();
  console.log(output);

  if (!urlFound) {
    const match = output.match(/https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com/);
    if (match) {
      urlFound = true;
      const url = match[0];
      console.log(`\n[TUNNEL] URL detected: ${url}`);
      updateBotUrl(url).then(ok => {
        if (ok) console.log('[TUNNEL] URL saved to Supabase');
      });
    }
  }
});

tunnel.on('close', (code) => {
  console.log(`[TUNNEL] Cloudflared exited with code ${code}`);
  process.exit(code);
});

process.on('SIGINT', () => tunnel.kill());
process.on('SIGTERM', () => tunnel.kill());
