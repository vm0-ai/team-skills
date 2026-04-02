---
name: dev-stop
description: Stop the background development server
---

Stop the background development server gracefully.

## Workflow

### Step 1: Stop the Server

Kill the dev server processes:

```bash
pkill -f "turbo.*dev" 2>/dev/null
pkill -f "pnpm.*dev" 2>/dev/null
```

### Step 2: Verify Stopped

Check if processes are gone and Caddy is no longer responding:

```bash
pgrep -f "turbo.*dev" || echo "✅ No turbo dev processes found"
curl -k -s --connect-timeout 3 https://www.vm7.ai:8443/ > /dev/null 2>&1 && echo "⚠️ Server still responding" || echo "✅ Server is down"
```

### Step 3: Show Results

**If stopped successfully**:
```
✅ Dev server stopped successfully

You can start it again with `/dev-start`
```

**If process still detected**:
```
⚠️ Warning: Dev server process still detected

Try manual cleanup: pkill -f "pnpm dev"
```

**If no dev server was running**:
```
ℹ️ No dev server is currently running

Use `/dev-start` to start one
```
