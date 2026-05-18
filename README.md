# OpenClaw + Bright Data — Railway Template

> Deploy OpenClaw on Railway with **66 Bright Data web tools built in**. One click. No manual plugin setup. No getting blocked.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/mkYabD?...)
---

## What this is

[OpenClaw](https://openclaw.ai/) is a self-hosted AI agent gateway. It connects your AI model (Gemini, GPT, Claude) to a powerful agent that can browse the web, extract data, automate browsers, and run tasks on your behalf.

The problem: when your agent tries to access real websites — product pages, news sites, social platforms, anything with bot protection — it gets blocked. CAPTCHAs fail. Pages return 403s. Data comes back empty.

**This template solves that.**

It bundles the official **[Bright Data plugin](https://docs.brightdata.com/integrations/openclaw)** directly into your Railway deployment. Your agent gets 66 unblocked web tools from day one — no CLI commands, no manual configuration, no getting blocked.

---

## What you get

- ✅ **OpenClaw Gateway + Control UI** — full AI agent dashboard
- ✅ **Setup Wizard at `/setup`** — password-protected status page with live bootstrap log
- ✅ **Bright Data plugin pre-installed** — 66 tools ready on first boot
- ✅ **Persistent state** — config and credentials survive redeploys via Railway Volume
- ✅ **Auto-configured AI provider** — set your key in Variables, bootstrap handles the rest

---

## Quick Start (2 steps)

### Step 1 — Click Deploy

Click the **Deploy on Railway** button above. Railway will create a new project from this template.

> ⚠️ **Important:** After the first deploy attempt, you must add a **Volume mounted at `/data`** in your service settings. Without it the gateway cannot store its config and the deployment will fail. Go to your service → Settings → Add Volume → Mount path: `/data`

### Step 2 — Set your API keys in Railway Variables

| Variable | Description | Required? |
|---|---|---|
| `BRIGHTDATA_API_TOKEN` | Your Bright Data API key | ✅ Required |
| `SETUP_PASSWORD` | Password for the `/setup` wizard | ✅ Required |
| `OPENROUTER_API_KEY` | Free OpenRouter key — recommended default AI provider | ✅ Recommended |
| `OPENAI_API_KEY` | OpenAI key — alternative AI provider | Optional |
| `ANTHROPIC_API_KEY` | Anthropic key — alternative AI provider | Optional |
| `GEMINI_API_KEY` | Google Gemini key — alternative AI provider | Optional |
| `BRIGHTDATA_AS_DEFAULT_SEARCH` | Set `true` to route all web searches through Bright Data | Optional |
| `BRIGHTDATA_UNLOCKER_ZONE` | Existing zone name (auto-created if blank) | Optional |
| `BRIGHTDATA_BROWSER_ZONE` | Existing zone name (auto-created if blank) | Optional |

**Get your Bright Data API key:** [brightdata.com/cp/setting/users](https://brightdata.com/cp/setting/users) → Generate API key

**Get a free OpenRouter key:** [openrouter.ai/keys](https://openrouter.ai/keys)

> **Why OpenRouter?** The Bright Data plugin loads 66 tools, making the system prompt 56K–80K tokens on every request. Groq free tier (12K TPM) fails on every call. OpenRouter's free Nemotron model handles this without rate limits.

Once your variables are set Railway will build, bootstrap, and start your agent automatically.

---

## Accessing your deployment

Once the build completes:

### Step 1 — Open the Setup Wizard
Visit `https://your-app.up.railway.app/setup`

- Enter any username and your `SETUP_PASSWORD`
- Wait for the status to show **DONE**
- Copy the **Gateway Token** displayed on the page
![Setup page showing DONE status](https://raw.githubusercontent.com/ReallyGreatTech/brightdata-railway/main/docs/images/setup-done.png)

### Step 2 — Open the OpenClaw UI
Click the **Open OpenClaw UI** button on the setup page

- Paste the Gateway Token when prompted
- You're in — your agent is ready

### Step 3 — Start chatting
Type a prompt and your agent will use Bright Data tools to fetch live web data.
![OpenClaw UI dashboard](https://raw.githubusercontent.com/ReallyGreatTech/brightdata-railway/main/docs/images/openclaw-ui.png)

---

## Test prompts

Once your agent is live, try these prompts to verify everything is working:

**Web search:**
```
Use brightdata_search to search for "latest AI news" and return the top 5 results with their URLs.
```

**Page scraping (works on bot-protected sites):**
```
Use brightdata_scrape on https://news.ycombinator.com and list the top 5 story titles.
```

**Browser automation:**
```
Use brightdata_browser_navigate to open https://example.com, then use brightdata_browser_screenshot to take a screenshot of the page.
```

**Structured Amazon data:**
```
Use brightdata_amazon_product to get the title, price, and rating for https://www.amazon.com/dp/B0D2Q9397Y
```

**LinkedIn data:**
```
Use brightdata_linkedin_person_profile to get the profile details for https://www.linkedin.com/in/satyanadella
```

---

## Available Bright Data tools (66 total)

| Category | Tools |
|---|---|
| **Web Search** | Google, Bing, Yandex with geo-targeting and pagination |
| **Scraping** | Bot-bypass scraping, batch URLs, multiple output formats |
| **Browser Automation** | Navigate, click, type, screenshot, scroll, wait, network inspection, form fill |
| **E-commerce** | Amazon, Walmart, eBay, Home Depot, Zara, Etsy, Best Buy |
| **Social Media** | Instagram, Facebook, TikTok, X (Twitter), YouTube, Reddit |
| **Professional** | LinkedIn profiles, companies, job listings, posts, people search |
| **Business Data** | Crunchbase, ZoomInfo, Google Maps reviews, Yahoo Finance |
| **Real Estate** | Zillow property listings |
| **Travel** | Booking.com hotel listings |
| **App Stores** | Google Play Store, Apple App Store |
| **AI Insights** | ChatGPT, Grok, Perplexity responses |
| **News** | Reuters news |

Full tool reference: [docs.brightdata.com/integrations/openclaw](https://docs.brightdata.com/integrations/openclaw#available-tools)

---

## How it differs from the base OpenClaw template

| Feature | Base OpenClaw Template | This Template |
|---|---|---|
| OpenClaw Gateway | ✓ | ✓ |
| Setup Wizard | ✓ | ✓ |
| Persistent Volume | ✓ | ✓ |
| Bright Data Plugin | Manual install required | ✅ Pre-installed |
| Web Unblocking | Not included | ✅ Built in |
| 66 Web Tools | Not included | ✅ Ready on boot |
| AI provider auto-config | Manual | ✅ Automatic |

---

## First boot explained

On the very first start, the container automatically:

1. Copies the pre-baked Bright Data plugin from the Docker image to the volume
2. Configures your `BRIGHTDATA_API_TOKEN`
3. Enables the plugin and registers all 66 tools
4. Registers your AI provider key
5. Writes a sentinel file so bootstrap only runs once
6. Starts the OpenClaw gateway

Visit `/setup` to watch the bootstrap log in real time. When status shows `DONE`, your agent is live.

---

## Local development

```bash
# Copy env file and fill in your keys
cp env.example .env

# Build and start
docker compose up --build

# Setup wizard: http://localhost:8080/setup
# OpenClaw UI:  http://localhost:8080/openclaw
```

---

## Frequently Asked Questions

**Do I need a paid Bright Data account?**
Yes — a Bright Data account with API access is required. The plugin will auto-create the proxy zones (`mcp_unlocker` and `mcp_browser`) on first use. You can sign up at [brightdata.com](https://brightdata.com).

**Which AI provider should I use?**
OpenRouter with a free key is the recommended default — it provides a 262K context model at no cost, which is essential for handling the 66-tool manifest. If you want faster responses, use a paid provider like Gemini or OpenAI.

**Why does the first response take a while?**
Response time depends on your AI provider and the tools being called. Free tier providers may be slower. For faster responses, use a paid AI provider key.

**Can I use Groq?**
Groq's free tier has a 12K TPM limit. The 66 Bright Data tools inflate every request to 56K+ tokens, causing 413 errors on every call. Only use Groq with a paid account.

**What happens if I redeploy?**
Your volume persists across redeploys. The bootstrap sentinel file prevents re-running the setup. Your config, credentials, and plugin state are all preserved.

**The OpenClaw UI shows "origin not allowed"**
Make sure `RAILWAY_PUBLIC_DOMAIN` is set in your Railway Variables to your deployment URL (e.g. `your-app.up.railway.app`). The bootstrap script uses this to configure allowed origins automatically.

**The setup page shows FAILED**
This usually means `BRIGHTDATA_API_TOKEN` is missing or incorrect. Set it in Railway Variables and redeploy. The bootstrap will run again on the next boot.

**Plugin tools not appearing in the agent**
Visit `/setup` and check the bootstrap log. If it shows DONE, the plugin is loaded. Try starting a fresh chat session.

---

## Troubleshooting

**Bootstrap failed / BRIGHTDATA_API_TOKEN not set**
Set the variable in Railway Variables → redeploy.

**413 errors on every request**
Switch from Groq to `OPENROUTER_API_KEY` — Groq free tier cannot handle the 66-tool context.

**Volume not mounted**
Your service must have a volume mounted at `/data`. Add it in service Settings → Volumes.

**Gateway token missing from setup page**
Wait for the bootstrap to complete (status: DONE) — the token is generated during gateway startup.

---

## Resources

- [OpenClaw documentation](https://docs.openclaw.ai)
- [Bright Data plugin docs](https://docs.brightdata.com/integrations/openclaw)
- [Bright Data dashboard](https://brightdata.com/cp)
- [OpenRouter free models](https://openrouter.ai/models?q=free)
- [Railway documentation](https://docs.railway.com)

---

## License

MIT