# OpenClaw + Bright Data — Railway Template

Run OpenClaw on Railway with **unblocked web access built in**. One click to deploy — no manual plugin setup, no getting blocked.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template)

---

## What this is

[OpenClaw](https://openclaw.ai/) is a self-hosted AI agent gateway that connects messaging apps (WhatsApp, Telegram, Discord, iMessage) to AI coding agents. It can browse the web, fill forms, extract data, and automate tasks.

The problem: when your OpenClaw agent tries to access real websites — product pages, news sites, social platforms, anything with bot protection — it gets blocked. CAPTCHAs fail. Pages return 403s. Data is empty.

This template solves that by bundling the **[Bright Data plugin](https://docs.brightdata.com/integrations/openclaw)** directly into your Railway deployment. Your agent gets 66 web tools from day one:

- Real-time web search (Google, Bing, Yandex with geo-targeting)
- Bot-bypass scraping via Bright Data's Web Unlocker
- Full browser automation routed through residential proxies
- Structured data from 50+ platforms (Amazon, LinkedIn, Instagram, TikTok, YouTube, Reddit, and more)

---

## What you get

- **OpenClaw Gateway + Control UI** at `/` and `/openclaw`
- **Setup Wizard** at `/setup` (password-protected)
- **Bright Data plugin pre-installed and enabled** — no CLI commands needed
- **Persistent state** via Railway Volume (config and credentials survive redeploys)

---

## Deploy in 2 steps

**Step 1: Click deploy**

Click the "Deploy on Railway" button above. Railway will fork this repo and create a new project with a persistent volume already configured.

**Step 2: Set your API keys in Railway Variables**

| Variable | Value | Required? |
|---|---|---|
| `BRIGHTDATA_API_TOKEN` | Your Bright Data API key | **Required** |
| `SETUP_PASSWORD` | Password for the /setup wizard | **Required** |
| `OPENROUTER_API_KEY` | Free OpenRouter key — recommended default AI provider | **Required (or one below)** |
| `OPENAI_API_KEY` | OpenAI key (paid) | Optional — alternative to OpenRouter |
| `ANTHROPIC_API_KEY` | Anthropic key (paid) | Optional — alternative to OpenRouter |
| `GEMINI_API_KEY` | Google AI key (paid) | Optional — alternative to OpenRouter |
| `BRIGHTDATA_AS_DEFAULT_SEARCH` | `true` to route all searches via Bright Data | Optional |
| `BRIGHTDATA_UNLOCKER_ZONE` | Existing zone name (auto-created if blank) | Optional |
| `BRIGHTDATA_BROWSER_ZONE` | Existing zone name (auto-created if blank) | Optional |

**Get your Bright Data API key:** https://brightdata.com/cp/setting/users → Generate API key

**Get a free OpenRouter key:** https://openrouter.ai/keys — the default model (`nvidia/nemotron-3-super-120b-a12b:free`) has 262K context and no rate limits, which is required for the 66-tool plugin manifest.

> **Why OpenRouter?** The Bright Data plugin loads 66 tools, making the system prompt 56K–80K tokens on every request. Groq free tier (12K TPM) fails on every call. OpenRouter's free Nemotron model handles this without rate limits.

That's it. Railway will build the container, run the Bright Data bootstrap on first boot, and your agent will be live.

---

## First boot

On the very first start, the container:

1. Installs `@brightdata/brightdata-plugin` via the OpenClaw CLI
2. Configures your API key
3. Enables the plugin and registers your AI provider
4. Writes a sentinel file so this only happens once
5. Starts the OpenClaw gateway

Visit `/setup` to watch the bootstrap log in real time. When status shows `DONE`, click the link to open OpenClaw.

---

## Try it immediately

Once your agent is live, paste these into your chat:

**Search the web:**
```
Use the brightdata_search tool to search for "latest AI news" and return the top 5 results.
```

**Scrape a page (bot-protected sites work):**
```
Use brightdata_scrape on https://example.com and summarize the content in 3 bullets.
```

**Automate a browser:**
```
Use brightdata_browser_navigate to open https://example.com, then use brightdata_browser_get_text to return the visible text.
```

**Get structured Amazon data:**
```
Use brightdata_amazon_product to get details for https://www.amazon.com/dp/B0D2Q9397Y
```

---

## Available Bright Data tools (66 total)

| Category | Tools |
|---|---|
| Web search | Google, Bing, Yandex — with geo-targeting and pagination |
| Scraping | Bot-bypass scraping, batch URLs, multiple output formats |
| Browser automation | Navigate, click, type, screenshot, scroll, wait, network inspection |
| Structured data | Amazon, Walmart, LinkedIn, Instagram, TikTok, YouTube, Reddit, and 40+ more |
| AI insights | ChatGPT, Grok, Perplexity responses |

Full tool reference: https://docs.brightdata.com/integrations/openclaw#available-tools

---

## Local testing

```bash
# Copy env file
cp env.example .env
# Fill in BRIGHTDATA_API_TOKEN, SETUP_PASSWORD, and OPENROUTER_API_KEY

# Build and run
docker compose up --build

# Setup wizard: http://localhost:8080/setup
```

---

## Troubleshooting

**Bootstrap failed / BRIGHTDATA_API_TOKEN not set**
Set the variable in Railway Variables → redeploy. The bootstrap script will run again on next boot (it deletes the sentinel file on failure).

**Agent says "no AI provider configured" or requests fail**
Set `OPENROUTER_API_KEY` in Railway Variables and redeploy. The bootstrap only registers your AI key on first boot — if the key was missing, you need to delete the sentinel file first: open the Railway shell and run `rm /data/.openclaw/.brightdata-bootstrapped`, then redeploy.

**Plugin tools not appearing in the agent**
Visit `/setup` and check the bootstrap log. If status is `DONE`, run `openclaw plugins inspect brightdata` in the Railway shell to verify the plugin is loaded.

**Zones not being created automatically**
The plugin auto-creates `mcp_unlocker` and `mcp_browser` zones on first use. If auto-creation fails, create them manually in your [Bright Data dashboard](https://brightdata.com/cp) and set `BRIGHTDATA_UNLOCKER_ZONE` / `BRIGHTDATA_BROWSER_ZONE` accordingly.

**Gateway not starting**
Check that your Volume is mounted at `/data`. Without persistent storage, OpenClaw can't write its config and the gateway won't start.

**413 errors on every request (if using Groq)**
Groq's free tier has a 12K TPM limit. The 66 Bright Data tools inflate every request to 56K+ tokens. Switch to `OPENROUTER_API_KEY` instead — it's free and handles large contexts.

---

## How it differs from the base OpenClaw template

| | Base template | This template |
|---|---|---|
| OpenClaw | ✓ | ✓ |
| Setup wizard | ✓ | ✓ |
| Persistent volume | ✓ | ✓ |
| Bright Data plugin | Manual install | **Pre-installed** |
| Web unblocking | Not included | **Built in** |
| 66 web tools | Not included | **Ready on boot** |

---

## Resources

- [OpenClaw documentation](https://docs.openclaw.ai)
- [Bright Data plugin docs](https://docs.brightdata.com/integrations/openclaw)
- [Bright Data plugin source](https://github.com/brightdata/openclaw-plugin)
- [Bright Data dashboard](https://brightdata.com/cp)

---

## License

MIT
