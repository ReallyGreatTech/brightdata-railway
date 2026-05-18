#!/usr/bin/env bash
# bootstrap-plugin.sh
#
# Installs and configures the Bright Data OpenClaw plugin on first boot.
# Safe to re-run: all operations are idempotent. Uses a sentinel file
# at $OPENCLAW_STATE_DIR/.brightdata-bootstrapped to skip on subsequent boots.
#
# Called by server.js before the OpenClaw gateway starts.

set -euo pipefail

STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
SENTINEL="$STATE_DIR/.brightdata-bootstrapped"

# ── Session cleanup — runs on every boot ─────────────────────────────────────
# Remove backup and trajectory files that accumulate context and inflate token counts
SESSION_DIR="$STATE_DIR/agents/main/sessions"
if [ -d "$SESSION_DIR" ]; then
  BAK_COUNT=$(find "$SESSION_DIR" -name '*.bak-*' 2>/dev/null | wc -l)
  TRAJ_COUNT=$(find "$SESSION_DIR" -name '*.trajectory.jsonl' 2>/dev/null | wc -l)
  if [ "$BAK_COUNT" -gt 0 ] || [ "$TRAJ_COUNT" -gt 0 ]; then
    echo "[brightdata-bootstrap] Cleaning up $BAK_COUNT backup and $TRAJ_COUNT trajectory files..."
    find "$SESSION_DIR" -name '*.bak-*' -delete 2>/dev/null || true
    find "$SESSION_DIR" -name '*.trajectory.jsonl' -delete 2>/dev/null || true
    echo "[brightdata-bootstrap] Session cleanup complete."
  fi
fi

# ── Control UI gateway config — runs on every boot ───────────────────────────
# These two settings fix cross-origin and device-pairing blockers on Railway.
# They must re-run on every boot because RAILWAY_PUBLIC_DOMAIN can change and
# the sentinel file would otherwise skip them on subsequent deploys.

# 1. Whitelist the Railway public domain so WebSocket connections are accepted.
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  echo "[brightdata-bootstrap] Setting allowed origin: https://${RAILWAY_PUBLIC_DOMAIN}"
  openclaw config set gateway.controlUi.allowedOrigins "[\"https://${RAILWAY_PUBLIC_DOMAIN}\"]"
fi

# 2. Disable device-pairing requirement for the Control UI.
#    Without this users see "device pairing required" after entering their token.
#    The gateway token (visible at /setup) remains the authentication mechanism.
echo "[brightdata-bootstrap] Disabling Control UI device pairing requirement..."
openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth true

# 3. Trust localhost so Railway's reverse-proxy headers are accepted.
#    Without this the gateway logs "Proxy headers detected from untrusted address"
#    and rejects connections that originate through Railway's load balancer.
echo "[brightdata-bootstrap] Setting trusted proxies..."
openclaw config set gateway.trustedProxies '["127.0.0.1"]'

# ── Already done — skip ───────────────────────────────────────────────────────
if [ -f "$SENTINEL" ]; then
  echo "[brightdata-bootstrap] Plugin already configured — skipping."
  exit 0
fi

echo "[brightdata-bootstrap] First boot detected. Configuring Bright Data plugin..."

# ── Validate required env var ─────────────────────────────────────────────────
if [ -z "${BRIGHTDATA_API_TOKEN:-}" ]; then
  echo "[brightdata-bootstrap] ERROR: BRIGHTDATA_API_TOKEN is not set."
  echo "[brightdata-bootstrap] Set it in your Railway Variables and redeploy."
  echo "[brightdata-bootstrap] Get your API key at: https://brightdata.com/cp/setting/users"
  exit 1
fi

# ── Install the plugin ────────────────────────────────────────────────────────
echo "[brightdata-bootstrap] Cleaning up existing plugin directory..."
rm -rf "$STATE_DIR/extensions/brightdata"
rm -rf "$STATE_DIR/extensions/.openclaw-install-stage-"*

# Check if we have a baked version in the image (faster than downloading)
if [ -d "/tmp/.openclaw/extensions/brightdata" ]; then
  echo "[brightdata-bootstrap] Found baked plugin. Copying essential files only (not node_modules)..."
  # We copy only the 3 files OpenClaw needs. node_modules is symlinked back to the
  # baked image path so externalized deps resolve without consuming volume space.
  # The full plugin tree is ~500MB; Railway free volumes are only 512MB.
  PLUGIN_SRC="/tmp/.openclaw/extensions/brightdata"
  PLUGIN_DEST="$STATE_DIR/extensions/brightdata"
  mkdir -p "$PLUGIN_DEST/dist"

  cp "$PLUGIN_SRC/dist/index.js"        "$PLUGIN_DEST/dist/index.js"
  cp "$PLUGIN_SRC/package.json"         "$PLUGIN_DEST/package.json"
  cp "$PLUGIN_SRC/openclaw.plugin.json" "$PLUGIN_DEST/openclaw.plugin.json"

  # Symlink node_modules from the baked image — available for the container's lifetime
  ln -sf "$PLUGIN_SRC/node_modules" "$PLUGIN_DEST/node_modules"

  # Point package.json main/extensions to the CJS bundle (not the raw .ts source)
  echo "[brightdata-bootstrap] Updating package.json entry point to dist/index.js..."
  python3 -c "
import json
p = '$PLUGIN_DEST/package.json'
with open(p) as f:
    pkg = json.load(f)
pkg['main'] = 'dist/index.js'
if 'openclaw' in pkg and 'extensions' in pkg['openclaw']:
    pkg['openclaw']['extensions'] = ['./dist/index.js']
with open(p, 'w') as f:
    json.dump(pkg, f, indent=2)
print('Updated package.json main -> dist/index.js')
" 2>/dev/null || echo "[brightdata-bootstrap] Warning: Could not update package.json (non-fatal)"

  # Register it manually via config to bypass the stuck 'npm install'
  echo "[brightdata-bootstrap] Registering plugin in config..."
  openclaw config set plugins.entries.brightdata.enabled true

  # Copy pre-generated openclaw.json (gateway registration metadata)
  if [ -f "/tmp/.openclaw/openclaw.json" ] && [ ! -f "$STATE_DIR/openclaw.json" ]; then
    cp "/tmp/.openclaw/openclaw.json" "$STATE_DIR/openclaw.json"
  fi
else
  echo "[brightdata-bootstrap] Baked plugin not found. Downloading @brightdata/brightdata-plugin..."
  # Fallback (slow) — no volume space concern since openclaw manages the install
  openclaw plugins install @brightdata/brightdata-plugin \
    --dangerously-force-unsafe-install
fi

# ── Enable the gateway service ──────────────────────────────────────────────
# Ensure the gateway is in 'local' mode for Docker
openclaw config set gateway.mode local

# ── Configure the API key ─────────────────────────────────────────────────────
echo "[brightdata-bootstrap] Configuring API key..."
openclaw config set plugins.entries.brightdata.config.webSearch.apiKey "$BRIGHTDATA_API_TOKEN"

# ── Configure optional zone overrides ────────────────────────────────────────
if [ -n "${BRIGHTDATA_UNLOCKER_ZONE:-}" ] && [ "$BRIGHTDATA_UNLOCKER_ZONE" != "mcp_unlocker" ]; then
  echo "[brightdata-bootstrap] Setting custom unlocker zone: $BRIGHTDATA_UNLOCKER_ZONE"
  openclaw config set plugins.entries.brightdata.config.webSearch.unlockerZone "$BRIGHTDATA_UNLOCKER_ZONE"
fi

if [ -n "${BRIGHTDATA_BROWSER_ZONE:-}" ] && [ "$BRIGHTDATA_BROWSER_ZONE" != "mcp_browser" ]; then
  echo "[brightdata-bootstrap] Setting custom browser zone: $BRIGHTDATA_BROWSER_ZONE"
  openclaw config set plugins.entries.brightdata.config.webSearch.browserZone "$BRIGHTDATA_BROWSER_ZONE"
fi

# ── Enable the plugin ─────────────────────────────────────────────────────────
echo "[brightdata-bootstrap] Enabling plugin..."
# Use config set instead of 'plugins enable' to avoid interactive prompts
openclaw config set plugins.entries.brightdata.enabled true

# ── Allow plugin tools to be exposed to agents ───────────────────────────────
echo "[brightdata-bootstrap] Allowing plugin tool group..."
openclaw config set tools.alsoAllow '["group:plugins"]'

# ── Optionally set as default web search provider ────────────────────────────
if [ "${BRIGHTDATA_AS_DEFAULT_SEARCH:-false}" = "true" ]; then
  echo "[brightdata-bootstrap] Setting Bright Data as default web search provider..."
  openclaw config set tools.web.search.provider brightdata
fi
# ── Copy pre-baked gateway runtime deps to persistent volume ─────────────────
echo "[brightdata-bootstrap] Copying pre-baked gateway runtime deps..."
if [ -d "/tmp/.openclaw/plugin-runtime-deps" ]; then
  mkdir -p "$STATE_DIR/plugin-runtime-deps"
  cp -rp /tmp/.openclaw/plugin-runtime-deps/. "$STATE_DIR/plugin-runtime-deps/"
  echo "[brightdata-bootstrap] Gateway runtime deps copied successfully."
fi

# ── Register AI provider key so agents can use it ────────────────────────────
echo "[brightdata-bootstrap] Registering AI provider key..."
AGENT_DIR="$STATE_DIR/agents/main/agent"
mkdir -p "$AGENT_DIR"

if [ -n "${GEMINI_API_KEY:-}" ]; then
  echo "[brightdata-bootstrap] Writing Gemini API key to auth-profiles.json..."
  cat > "$AGENT_DIR/auth-profiles.json" << AUTHEOF
{
  "version": 1,
  "profiles": {
    "google:gemini": {
      "type": "token",
      "provider": "google",
      "token": "${GEMINI_API_KEY}"
    }
  }
}
AUTHEOF
  echo "[brightdata-bootstrap] Setting default model to google/gemini-2.0-flash..."
  openclaw models set google/gemini-2.0-flash
  echo "[brightdata-bootstrap] Gemini API key registered."
elif [ -n "${OPENAI_API_KEY:-}" ]; then
  echo "[brightdata-bootstrap] Writing OpenAI API key to auth-profiles.json..."
  cat > "$AGENT_DIR/auth-profiles.json" << AUTHEOF
{
  "version": 1,
  "profiles": {
    "openai:manual": {
      "type": "token",
      "provider": "openai",
      "token": "${OPENAI_API_KEY}"
    }
  }
}
AUTHEOF
  echo "[brightdata-bootstrap] Setting default model to openai/gpt-4o..."
  openclaw models set openai/gpt-4o
  echo "[brightdata-bootstrap] OpenAI API key registered."
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "[brightdata-bootstrap] Writing Anthropic API key to auth-profiles.json..."
  cat > "$AGENT_DIR/auth-profiles.json" << AUTHEOF
{
  "version": 1,
  "profiles": {
    "anthropic:manual": {
      "type": "token",
      "provider": "anthropic",
      "token": "${ANTHROPIC_API_KEY}"
    }
  }
}
AUTHEOF
  echo "[brightdata-bootstrap] Setting default model to anthropic/claude-sonnet-4-6..."
  openclaw models set anthropic/claude-sonnet-4-6
  echo "[brightdata-bootstrap] Anthropic API key registered."
elif [ -n "${GROQ_API_KEY:-}" ]; then
  echo "[brightdata-bootstrap] Writing Groq API key to auth-profiles.json..."
  # WARNING: Groq free tier has a 12K TPM limit. The brightdata plugin loads 66 tools,
  # making every request ~56K+ tokens — this will 413 on every call on a free account.
  # Use Groq only with a paid account, or prefer OPENROUTER_API_KEY for a free alternative.
  cat > "$AGENT_DIR/auth-profiles.json" << AUTHEOF
{
  "version": 1,
  "profiles": {
    "groq:manual": {
      "type": "token",
      "provider": "groq",
      "token": "${GROQ_API_KEY}"
    }
  }
}
AUTHEOF
  echo "[brightdata-bootstrap] Setting default model to groq/llama-3.3-70b-versatile..."
  openclaw models set groq/llama-3.3-70b-versatile
  echo "[brightdata-bootstrap] Groq API key registered (note: free tier TPM limit may cause 413 errors)."
elif [ -n "${OPENROUTER_API_KEY:-}" ]; then
  echo "[brightdata-bootstrap] Writing OpenRouter API key to auth-profiles.json..."
  cat > "$AGENT_DIR/auth-profiles.json" << AUTHEOF
{
  "version": 1,
  "profiles": {
    "openrouter:manual": {
      "type": "token",
      "provider": "openrouter",
      "token": "${OPENROUTER_API_KEY}"
    }
  }
}
AUTHEOF
  echo "[brightdata-bootstrap] Setting default model to openrouter/nvidia/nemotron-3-super-120b-a12b:free..."
  openclaw models set openrouter/nvidia/nemotron-3-super-120b-a12b:free
  echo "[brightdata-bootstrap] OpenRouter API key registered."
else
  echo "[brightdata-bootstrap] WARNING: No AI provider key found."
  echo "[brightdata-bootstrap] Set GEMINI_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY, GROQ_API_KEY, or OPENROUTER_API_KEY."
fi

# ── Generate and persist a fixed gateway auth token ──────────────────────────
# The gateway generates a random in-memory token each boot if none is configured,
# which means server.js can never find it in openclaw.json. Setting it here once
# writes the value to openclaw.json so it survives restarts and appears on /setup.
echo "[brightdata-bootstrap] Generating persistent gateway auth token..."
openclaw config set gateway.auth.mode token
openclaw config set gateway.auth.token "$(openssl rand -hex 32)"
echo "[brightdata-bootstrap] Gateway auth token saved to openclaw.json."

# ── Write sentinel so we skip on next boot ────────────────────────────────────
mkdir -p "$STATE_DIR"
echo "Bootstrapped at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SENTINEL"

echo "[brightdata-bootstrap] Done. Plugin installed, configured, and enabled."
echo "[brightdata-bootstrap] Your OpenClaw agent now has 66 Bright Data web tools."
