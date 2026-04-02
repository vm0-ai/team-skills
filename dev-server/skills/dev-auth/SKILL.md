---
name: dev-auth
description: Authenticate with local development server and get CLI token
---

Authenticate with local development server and get CLI token.

## Prerequisites

- Dev server must be running (use `/dev-start` first)
- Clerk test credentials must be configured in environment

## Workflow

### Step 1: Check Dev Server Running

Check if dev server is accessible via the Caddy reverse proxy:

```bash
if curl -k -s --connect-timeout 3 https://www.vm7.ai:8443/ > /dev/null 2>&1; then
  echo "✅ Dev server is accessible at https://www.vm7.ai:8443"
else
  echo "❌ Dev server is not accessible"
  echo "Please run /start first or check if server is running"
  exit 1
fi
```

### Step 2: Check Required Environment Variables

Check and ensure all required environment variables are set in `turbo/apps/web/.env.local`:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
ENV_FILE="$PROJECT_ROOT/turbo/apps/web/.env.local"

# Check NEXT_PUBLIC_APP_URL
if ! grep -q "^NEXT_PUBLIC_APP_URL=" "$ENV_FILE" 2>/dev/null; then
  echo "⚠️ NEXT_PUBLIC_APP_URL not found, adding it..."
  echo "NEXT_PUBLIC_APP_URL=http://localhost:3000" >> "$ENV_FILE"
  echo "✅ Added NEXT_PUBLIC_APP_URL to .env.local"
  echo "⚠️ Note: Dev server needs restart to pick up this change"
fi

# Check NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY
if ! grep -q "^NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=" "$ENV_FILE" 2>/dev/null; then
  echo "❌ NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY not found in .env.local"
  echo "Please run: script/sync-env.sh"
  exit 1
fi

# Check CLERK_SECRET_KEY
if ! grep -q "^CLERK_SECRET_KEY=" "$ENV_FILE" 2>/dev/null; then
  echo "❌ CLERK_SECRET_KEY not found in .env.local"
  echo "Please run: script/sync-env.sh"
  exit 1
fi

echo "✅ All required environment variables are present"
```

### Step 3: Build and Install CLI Globally

Build and install the CLI globally:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/turbo/apps/cli" && pnpm build && pnpm link --global
```

### Step 4: Run Authentication Automation

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT" && npx tsx e2e/cli-auth-automation.ts $(printenv VM0_API_URL)
```

This script:
- Spawns `vm0 auth login` with the current `VM0_API_URL`
- Launches Playwright browser in headless mode
- Logs in via Clerk using `$(hostname)+clerk_test@vm0.ai`
- Automatically enters the CLI device code
- Clicks "Authorize Device" button
- Saves token to `~/.vm0/config.json`

### Step 5: Verify Authentication

```bash
cat ~/.vm0/config.json
```

### Step 6: Display Results

```
✅ CLI authentication successful!

Auth token saved to: ~/.vm0/config.json

You can now use the CLI with local dev server:
- vm0 auth status
- vm0 project list
```

## Error Handling

If authentication fails:
- Check dev server logs with `/dev-logs`
- Verify Clerk credentials in `turbo/apps/web/.env.local`
- Ensure Playwright browser is installed
