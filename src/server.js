/**
 * server.js
 *
 * Wrapper server for the OpenClaw + Bright Data Railway template.
 *
 * Responsibilities:
 *   1. On first boot: runs the Bright Data plugin bootstrap script
 *   2. Serves the /setup wizard (password-protected)
 *   3. Reverse-proxies all other traffic (HTTP + WebSocket) to the local
 *      OpenClaw gateway process
 */

import http from 'http';
import { spawn } from 'child_process';
import { existsSync, mkdirSync, readFileSync } from 'fs';
import { createRequire } from 'module';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const httpProxy = require('http-proxy');

// ── Config ────────────────────────────────────────────────────────────────────
const PORT = parseInt(process.env.PORT ?? '8080', 10);
const SETUP_PASS = process.env.SETUP_PASSWORD ?? 'changeme';
const GATEWAY_PORT = 18789; // OpenClaw gateway actual port

const STATE_DIR = process.env.OPENCLAW_STATE_DIR ?? '/data/.openclaw';
const WORKSPACE_DIR = process.env.OPENCLAW_WORKSPACE_DIR ?? '/data/workspace';

mkdirSync(STATE_DIR, { recursive: true });
mkdirSync(WORKSPACE_DIR, { recursive: true });

// ── Proxy to gateway ──────────────────────────────────────────────────────────
const proxy = httpProxy.createProxyServer({
  target: `http://localhost:${GATEWAY_PORT}`,
  ws: true,
  changeOrigin: true,
});

proxy.on('error', (err, req, res) => {
  log(`[proxy:err] ${err.message}`);
  if (res && typeof res.writeHead === 'function' && !res.headersSent) {
    res.writeHead(502, { 'Content-Type': 'text/plain' });
    res.end('Gateway not ready. Check /setup for status.');
  } else if (res && typeof res.end === 'function') {
    res.end();
  }
});

// ── Basic auth helper ─────────────────────────────────────────────────────────
function isAuthorized(req) {
  const auth = req.headers['authorization'];
  if (!auth) return false;
  const [, encoded] = auth.split(' ');
  const [, pass] = Buffer.from(encoded ?? '', 'base64').toString().split(':');
  return pass === SETUP_PASS;
}

function requireAuth(res) {
  res.writeHead(401, {
    'WWW-Authenticate': 'Basic realm="OpenClaw Setup"',
    'Content-Type': 'text/plain',
  });
  res.end('Unauthorized');
}

// ── Bootstrap state ───────────────────────────────────────────────────────────
let bootstrapStatus = 'pending'; // pending | running | done | error
let bootstrapLog = [];
let gatewayProcess = null;

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  bootstrapLog.push(line);
  if (bootstrapLog.length > 500) bootstrapLog = bootstrapLog.slice(-500);
}

// ── Run bootstrap then start gateway ─────────────────────────────────────────
async function bootstrap() {
  bootstrapStatus = 'running';
  log('Starting Bright Data plugin bootstrap...');

  const scriptPath = path.join(__dirname, '..', 'scripts', 'bootstrap-plugin.sh');
  const child = spawn('bash', [scriptPath], {
    env: process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  child.stdout.on('data', (data) => {
    const lines = data.toString().split('\n');
    lines.forEach(line => { if (line.trim()) log(line.trim()); });
  });

  child.stderr.on('data', (data) => {
    const lines = data.toString().split('\n');
    lines.forEach(line => { if (line.trim()) log(`[err] ${line.trim()}`); });
  });

  child.on('close', (code) => {
    if (code === 0) {
      bootstrapStatus = 'done';
      log('Bootstrap complete. Starting OpenClaw gateway...');
      startGateway();
    } else {
      bootstrapStatus = 'error';
      log(`Bootstrap failed with exit code ${code}`);
      log('Fix BRIGHTDATA_API_TOKEN in Railway Variables, then redeploy.');
    }
  });
}

function startGateway() {
  gatewayProcess = spawn('openclaw', ['gateway', 'run'], {
    env: {
      ...process.env,
      OPENCLAW_STATE_DIR: STATE_DIR,
      OPENCLAW_WORKSPACE_DIR: WORKSPACE_DIR,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  gatewayProcess.stdout.on('data', d => log(`[gateway] ${d.toString().trim()}`));
  gatewayProcess.stderr.on('data', d => log(`[gateway:err] ${d.toString().trim()}`));
  gatewayProcess.on('exit', code => {
    log(`Gateway exited with code ${code}. Restarting in 5s...`);
    setTimeout(startGateway, 5000);
  });
}

// ── Setup page HTML ───────────────────────────────────────────────────────────
function setupPage() {
  const statusColor = {
    pending: '#888',
    running: '#f0a500',
    done: '#22c55e',
    error: '#ef4444',
  }[bootstrapStatus] ?? '#888';

  const gatewayUrl = process.env.RAILWAY_PUBLIC_DOMAIN
    ? `https://${process.env.RAILWAY_PUBLIC_DOMAIN}/openclaw`
    : `http://localhost:${PORT}/openclaw`;

  let gatewayToken = 'Not generated yet';
  try {
    const configPath = path.join(STATE_DIR, 'openclaw.json');
    if (existsSync(configPath)) {
      const config = JSON.parse(readFileSync(configPath, 'utf8'));
      gatewayToken = config.gateway?.auth?.token || 'Token not found in config';
    }
  } catch (e) {
    gatewayToken = 'Error reading token';
  }

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>OpenClaw + Bright Data — Setup</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:system-ui,sans-serif;background:#0f0f0f;color:#e5e5e5;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px}
    .card{background:#1a1a1a;border:1px solid #2a2a2a;border-radius:12px;padding:36px;max-width:680px;width:100%}
    h1{font-size:20px;font-weight:600;margin-bottom:4px}
    .subtitle{color:#888;font-size:14px;margin-bottom:28px}
    .badge{display:inline-block;padding:3px 10px;border-radius:999px;font-size:12px;font-weight:600;background:${statusColor}22;color:${statusColor};border:1px solid ${statusColor}44;margin-bottom:20px}
    .section{margin-bottom:24px}
    h2{font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.05em;color:#888;margin-bottom:10px}
    .log{background:#0f0f0f;border:1px solid #2a2a2a;border-radius:8px;padding:14px;font-family:monospace;font-size:12px;line-height:1.6;color:#a3a3a3;max-height:240px;overflow-y:auto;white-space:pre-wrap;word-break:break-all}
    .row{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:10px}
    .btn{display:inline-flex;align-items:center;gap:6px;padding:9px 16px;border-radius:8px;font-size:13px;font-weight:500;text-decoration:none;border:none;cursor:pointer;transition:opacity .15s}
    .btn-primary{background:#2563eb;color:#fff}
    .btn-secondary{background:#2a2a2a;color:#e5e5e5}
    .btn:hover{opacity:.85}
    .env-table{width:100%;border-collapse:collapse;font-size:13px}
    .env-table td{padding:7px 10px;border-bottom:1px solid #2a2a2a}
    .env-table td:first-child{color:#888;width:42%}
    .tag{display:inline-block;padding:2px 8px;border-radius:4px;font-size:11px;font-weight:600}
    .tag-set{background:#16a34a22;color:#22c55e;border:1px solid #16a34a44}
    .tag-missing{background:#ef444422;color:#ef4444;border:1px solid #ef444444}
  </style>
  <meta http-equiv="refresh" content="10"/>
</head>
<body>
<div class="card">
  <h1>OpenClaw + Bright Data</h1>
  <p class="subtitle">Railway deployment setup — auto-refreshes every 10 seconds</p>

  <span class="badge">${bootstrapStatus.toUpperCase()}</span>

  <div class="section">
    <h2>Configuration</h2>
    <table class="env-table">
      <tr>
        <td>BRIGHTDATA_API_TOKEN</td>
        <td>${process.env.BRIGHTDATA_API_TOKEN
      ? '<span class="tag tag-set">SET ✓</span>'
      : '<span class="tag tag-missing">NOT SET — required</span>'}</td>
      </tr>
      <tr>
        <td>AI provider key</td>
        <td>${(process.env.OPENROUTER_API_KEY || process.env.OPENAI_API_KEY || process.env.ANTHROPIC_API_KEY || process.env.GEMINI_API_KEY || process.env.GROQ_API_KEY)
      ? '<span class="tag tag-set">SET ✓</span>'
      : '<span class="tag tag-missing">NOT SET — set OPENROUTER_API_KEY (free)</span>'}</td>
      </tr>
      <tr>
        <td>Unlocker zone</td>
        <td>${process.env.BRIGHTDATA_UNLOCKER_ZONE ?? 'mcp_unlocker (default)'}</td>
      </tr>
      <tr>
        <td>Browser zone</td>
        <td>${process.env.BRIGHTDATA_BROWSER_ZONE ?? 'mcp_browser (default)'}</td>
      </tr>
      <tr>
        <td>Default search provider</td>
        <td>${process.env.BRIGHTDATA_AS_DEFAULT_SEARCH === 'true' ? 'Bright Data' : 'OpenClaw default'}</td>
      </tr>
      <tr>
        <td>State dir</td>
        <td>${STATE_DIR}</td>
      </tr>
    </table>
  </div>

  ${bootstrapStatus === 'done' ? `
  <div class="section">
    <h2>Dashboard Access</h2>
    <div class="row">
      <a class="btn btn-primary" href="${gatewayUrl}" target="_blank">Open OpenClaw UI</a>
    </div>
    <div style="margin-top:15px; padding:12px; background:#000; border:1px dashed #444; border-radius:8px">
      <p style="font-size:12px; color:#888; margin-bottom:6px">Gateway Token (Copy this into the Dashboard Login):</p>
      <code style="font-size:14px; color:#22c55e; word-break:break-all">${gatewayToken}</code>
    </div>
    <p style="font-size:13px;color:#888;margin-top:12px">Your agent has 66 Bright Data tools for web search, scraping, browser automation, and structured data.</p>
  </div>` : ''}

  ${bootstrapStatus === 'error' ? `
  <div class="section">
    <h2>Fix required</h2>
    <p style="font-size:13px;color:#ef4444;margin-bottom:10px">Bootstrap failed. Set <strong>BRIGHTDATA_API_TOKEN</strong> in Railway Variables and redeploy.</p>
    <a class="btn btn-secondary" href="https://brightdata.com/cp/setting/users" target="_blank">Get API key →</a>
  </div>` : ''}

  <div class="section">
    <h2>Bootstrap log</h2>
    <div class="log">${bootstrapLog.join('\n') || 'Waiting...'}</div>
  </div>

  <div class="section">
    <h2>Quick test prompts</h2>
    <div class="log">Search the web:
  Use brightdata_search to search for "latest AI news" and return the top 5 results.

Scrape a page:
  Use brightdata_scrape on https://example.com and summarize in 3 bullets.

Automate a browser:
  Use brightdata_browser_navigate to open https://example.com,
  then brightdata_browser_get_text to return the visible text.</div>
  </div>
</div>
</body>
</html>`;
}

// ── HTTP server ───────────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  const url = req.url ?? '/';

  // Health check (unauthenticated — Railway needs this)
  if (url === '/setup/healthz' || url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, bootstrap: bootstrapStatus }));
    return;
  }

  // Setup page (password-protected)
  if (url.startsWith('/setup')) {
    if (!isAuthorized(req)) { requireAuth(res); return; }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(setupPage());
    return;
  }

  // Everything else → proxy to OpenClaw gateway
  proxy.web(req, res);
});

// WebSocket proxy
server.on('upgrade', (req, socket, head) => {
  proxy.ws(req, socket, head);
});

server.listen(PORT, '0.0.0.0', () => {
  log(`Wrapper listening on port ${PORT}`);
  log(`Setup wizard: /setup (password: ${SETUP_PASS})`);
  bootstrap();
});
