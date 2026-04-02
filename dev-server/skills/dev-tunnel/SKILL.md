---
name: dev-tunnel
description: Full dev setup with tunnel (automatic) and CLI authentication
context: main
---

Full development environment setup with Cloudflare tunnel and CLI authentication. Useful for webhook testing.

**Note**: Since issue #1726, the web app automatically starts a Cloudflare tunnel when running `pnpm dev`. This operation is useful when you need the **complete setup** including CLI authentication.

## What It Does

- Installs dependencies and builds project
- Starts dev server (tunnel is now automatic for web app)
- Installs E2E dependencies and Playwright
- Installs and authenticates CLI globally

## Workflow

### Step 1: Install Dependencies

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/turbo" && pnpm install
```

### Step 2: Build Project

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/turbo" && pnpm build
```

### Step 3: Start Dev Server and Runner

Use Bash tool with `run_in_background: true` for **both** commands in parallel (two separate Bash calls in the same message):

**Dev server** (use `tee` to persist logs for `/dev-logs` after context compaction):
```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/turbo" && pnpm dev 2>&1 | tee "$PROJECT_ROOT/turbo/.dev-server.log"
```

**Runner:**
```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/turbo" && pnpm runner
```

Both return a task_id for monitoring. The web app will automatically start a Cloudflare tunnel. The runner takes several minutes to initialize but doesn't block the app — only chat/agent features need it.

### Step 4: Wait for Tunnel URL

Use TaskOutput with the task_id from Step 3 to monitor the background task output. Look for:
- `[tunnel] Tunnel URL:` followed by the URL
- `Ready in` (Next.js ready message)

Poll TaskOutput every few seconds until the tunnel URL appears (up to ~60 seconds). Extract the tunnel URL (format: `https://*.trycloudflare.com`).

If the tunnel URL does not appear within ~60 seconds, report the failure and let the user investigate.

### Step 5: Export VM0_API_URL

```bash
export VM0_API_URL=<tunnel-url>
```

### Step 6: Install E2E Dependencies

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/e2e" && pnpm install
```

### Step 7: Install Playwright Browser

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/e2e" && npx playwright install chromium
```

### Step 8: Install CLI Globally

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/turbo/apps/cli" && pnpm link --global
```

### Step 9: Run CLI Authentication

Read Clerk credentials from `turbo/apps/web/.env.local`:
- `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` → `CLERK_PUBLISHABLE_KEY`
- `CLERK_SECRET_KEY` → `CLERK_SECRET_KEY`

Then run:
```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/e2e" && \
CLERK_PUBLISHABLE_KEY=<publishable-key> \
CLERK_SECRET_KEY=<secret-key> \
npx tsx cli-auth-automation.ts $(printenv VM0_API_URL)
```

### Step 10: Verify Authentication

```bash
cat ~/.vm0/config.json
```

### Step 11: Display Results

```
✅ Dev server with tunnel started!
🔧 Runner deployment started in background (takes several minutes)

Local:   http://localhost:3000
Tunnel:  <tunnel-url>

VM0_API_URL exported to: <tunnel-url>

✅ CLI authentication successful!
Auth token saved to: ~/.vm0/config.json

The app is usable now. Chat/agent features will become available once the runner finishes initializing.

Use `/dev-stop` to stop the server.
```

## Technical Details

The web app's dev script (`turbo/apps/web/scripts/dev.sh`):
- Starts a Cloudflare tunnel using `cloudflared`
- Exposes localhost:3000 to the internet
- Sets `VM0_API_URL` environment variable
- Starts Next.js dev server with Turbopack

## Error Handling

If tunnel fails to start:
- Check if `cloudflared` is installed
- Check tunnel logs: `tail -f /tmp/cloudflared-dev.log`

If authentication fails:
- Check dev server logs with `/dev-logs`
- Verify Clerk credentials in `turbo/apps/web/.env.local`
- Ensure Playwright browser is installed
