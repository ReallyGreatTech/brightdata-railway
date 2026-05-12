# ── Stage 1: Base image with Node + Chromium deps ───────────────────────────
FROM node:22-bookworm-slim AS base

# Chromium system dependencies (required by OpenClaw's browser agent)
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    wget \
    ca-certificates \
    curl \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# ── Stage 2: App layer ────────────────────────────────────────────────────────
FROM base AS app

WORKDIR /app

# Install pnpm globally
RUN npm install -g pnpm

# Copy package files
COPY package.json pnpm-lock.yaml* ./

# Install wrapper server dependencies
RUN pnpm install --no-frozen-lockfile --prod

# Speed up plugin installation by using the system Chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true

# Install OpenClaw globally (Cached)
RUN npm install -g openclaw

# Pre-bake the plugin into a temp directory (Cached)
# Build from source since plugin ships TypeScript only (v1.0.3)
# Use CJS output with --external:openclaw so JITI can alias the SDK correctly.
# ESM output caused TypeError (import.meta.url=undefined) when JITI transforms ESM→CJS.
RUN mkdir -p /tmp/brightdata-src && \
    cd /tmp/brightdata-src && \
    npm pack @brightdata/brightdata-plugin && \
    tar -xzf brightdata-brightdata-plugin-*.tgz && \
    cd package && \
    npm install --ignore-scripts && \
    node_modules/.bin/esbuild index.ts \
      --bundle --platform=node --format=cjs \
      --outfile=dist/index.js \
      --external:openclaw \
      --external:@anthropic-ai/sdk \
      --external:openai \
      --external:playwright \
      --external:playwright-core \
      --allow-overwrite && \
    OPENCLAW_STATE_DIR=/tmp/.openclaw openclaw plugins install /tmp/brightdata-src/package \
      --dangerously-force-unsafe-install && \
    node -e "const fs=require('fs'),p='/tmp/.openclaw/extensions/brightdata/openclaw.plugin.json',m=JSON.parse(fs.readFileSync(p,'utf8'));m.contracts={tools:['brightdata_search','brightdata_scrape','brightdata_search_batch','brightdata_scrape_batch','brightdata_browser_navigate','brightdata_browser_go_back','brightdata_browser_go_forward','brightdata_browser_snapshot','brightdata_browser_click','brightdata_browser_type','brightdata_browser_screenshot','brightdata_browser_get_html','brightdata_browser_get_text','brightdata_browser_scroll','brightdata_browser_scroll_to','brightdata_browser_wait_for','brightdata_browser_network_requests','brightdata_browser_fill_form','brightdata_amazon_product','brightdata_amazon_product_reviews','brightdata_amazon_product_search','brightdata_walmart_product','brightdata_walmart_seller','brightdata_ebay_product','brightdata_homedepot_products','brightdata_zara_products','brightdata_etsy_products','brightdata_bestbuy_products','brightdata_linkedin_person_profile','brightdata_linkedin_company_profile','brightdata_linkedin_job_listings','brightdata_linkedin_posts','brightdata_linkedin_people_search','brightdata_crunchbase_company','brightdata_zoominfo_company_profile','brightdata_instagram_profiles','brightdata_instagram_posts','brightdata_instagram_reels','brightdata_instagram_comments','brightdata_facebook_posts','brightdata_facebook_marketplace_listings','brightdata_facebook_company_reviews','brightdata_facebook_events','brightdata_tiktok_profiles','brightdata_tiktok_posts','brightdata_tiktok_shop','brightdata_tiktok_comments','brightdata_google_maps_reviews','brightdata_google_shopping','brightdata_google_play_store','brightdata_apple_app_store','brightdata_reuter_news','brightdata_github_repository_file','brightdata_yahoo_finance_business','brightdata_x_posts','brightdata_x_profile_posts','brightdata_zillow_properties_listing','brightdata_booking_hotel_listings','brightdata_youtube_profiles','brightdata_youtube_comments','brightdata_reddit_posts','brightdata_youtube_videos','brightdata_chatgpt_ai_insights','brightdata_grok_ai_insights','brightdata_perplexity_ai_insights']};fs.writeFileSync(p,JSON.stringify(m,null,2));console.log('Patched contracts.tools ('+m.contracts.tools.length+' tools)');"
# Pre-install gateway runtime dependencies so the gateway starts instantly
# Without this, OpenClaw downloads these 7 packages on every first boot (slow)
# NOTE: path must match the check in scripts/bootstrap-plugin.sh
RUN npm install --prefix /tmp/.openclaw/plugin-runtime-deps \
    @homebridge/ciao@1.3.6 \
    @modelcontextprotocol/sdk@1.29.0 \
    acpx@0.6.1 \
    commander@14.0.3 \
    express@5.2.1 \
    playwright-core@1.59.1 \
    undici@8.1.0

# Copy wrapper server source (Only this layer re-runs if code changes)
COPY src/ ./src/

# ── Runtime env defaults (overrideable at deploy time) ───────────────────────
ENV NODE_ENV=production
ENV OPENCLAW_STATE_DIR=/data/.openclaw
ENV OPENCLAW_WORKSPACE_DIR=/data/workspace

# Bright Data plugin env vars — user must supply BRIGHTDATA_API_TOKEN
ENV BRIGHTDATA_UNLOCKER_ZONE=mcp_unlocker
ENV BRIGHTDATA_BROWSER_ZONE=mcp_browser

# ── Plugin bootstrap script ───────────────────────────────────────────────────
# This script runs once on first boot to install and enable the Bright Data
# plugin. Subsequent boots skip it (idempotent check via sentinel file).
COPY scripts/bootstrap-plugin.sh /app/scripts/bootstrap-plugin.sh
RUN chmod +x /app/scripts/bootstrap-plugin.sh

EXPOSE 8080

CMD ["node", "src/server.js"]