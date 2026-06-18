---
name: dev-start
description: Start the development server in background mode
context: main
---

Start the Turbo development server in background mode.

## Arguments

Your args are: `$ARGUMENTS`

Supports `--tunnel-hostname=<fqdn>` to use a fixed tunnel domain instead of the auto-generated one.

**Note**: The web app automatically starts a Cloudflare tunnel during dev startup (issue #1726). This means `VM0_API_URL` is set automatically and webhooks work out of the box. The web app takes ~15 seconds longer to start than other packages due to tunnel setup.

## Workflow

### Step 1: Ensure Local Hosts Mapping

Ensure every local `vm7.ai` development domain resolves to `127.0.0.1` before running status checks or opening the app. The platform app calls `https://api.vm7.ai:8443`; if `api.vm7.ai` resolves outside the container while `www.vm7.ai` and `app.vm7.ai` resolve locally, the web/app services can look healthy while platform API calls hang.

Use `sudo tee` to update `/etc/hosts`; do not use `sed -i` because `/etc/hosts` is often a mounted file in devcontainers and atomic rename can fail with `Device or resource busy`.

```bash
VM7_DOMAINS="vm7.ai www.vm7.ai app.vm7.ai api.vm7.ai docs.vm7.ai platform.vm7.ai"

needs_hosts_update=0
for domain in $VM7_DOMAINS; do
  if ! getent hosts "$domain" | awk '{print $1}' | grep -qx "127.0.0.1"; then
    needs_hosts_update=1
  fi
done

if [ "$needs_hosts_update" -eq 1 ]; then
  tmp_hosts=$(mktemp)
  awk '
    /(^|[[:space:]])(vm7|www[.]vm7|app[.]vm7|api[.]vm7|docs[.]vm7|platform[.]vm7)[.]ai([[:space:]]|$)/ { next }
    { print }
  ' /etc/hosts > "$tmp_hosts"
  printf "127.0.0.1 %s\n" "$VM7_DOMAINS" >> "$tmp_hosts"
  sudo tee /etc/hosts < "$tmp_hosts" >/dev/null
  rm -f "$tmp_hosts"
fi

getent hosts api.vm7.ai www.vm7.ai app.vm7.ai docs.vm7.ai
```

If this command cannot update `/etc/hosts` because `sudo` is unavailable or prompts for credentials, report that blocker before starting browser work; otherwise API calls from the platform can time out silently.

### Step 2: Pre-flight Check

Run the dev server status check. This verifies SSL certificates (regenerating if missing) and checks port accessibility:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/turbo" && pnpm dev:status
```

If all three services show `running`, the dev server is already up — display the output and stop. Otherwise, proceed to start the server.

### Step 3: Start Runner in Background

Start the runner first using Bash tool with `run_in_background: true` parameter. The runner takes several minutes to initialize, so we start it early to overlap with the prepare step.

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/turbo" && pnpm runner
```

This returns a task_id for monitoring.

**Note on runner**: The runner takes several minutes to initialize (cross-compile, upload, build rootfs/snapshots). The app works without it — only chat/agent interaction features require the runner. You will be notified when the runner background task completes.

### Step 4: Run prepare.sh

While the runner is initializing in the background, run `prepare.sh` to set up the environment (sync .env.local, install dependencies, run database migrations). This may take a few minutes — wait for it to complete:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT" && bash -c 'set -o pipefail; bash scripts/prepare.sh 2>&1 | tee /tmp/prepare-output.log'
```

#### If prepare.sh fails

If the command above exits with a non-zero code, do the following **before** reporting the failure to the user:

1. **Gather diagnostic info** by running:

```bash
echo "HOSTNAME: $(bash "$(git rev-parse --show-toplevel)/scripts/cn.sh")"
echo "BRANCH: $(git branch --show-current)"
echo "--- LAST 20 LINES ---"
tail -20 /tmp/prepare-output.log
```

2. **Determine the failed step**: inspect the output for `db:migrate` or `Database migrations failed`. If found, the failed step is `db:migrate`; otherwise, report it as `prepare.sh`.

3. **Send a Slack notification** to `#flaky-test` using the Slack MCP tool (`slack_send_message`) with the following message format:

```
🔴 Dev server prepare failed on `<hostname>` (branch: `<branch>`)

**Failed step:** <prepare.sh or db:migrate>
**Error snippet:**
\`\`\`
<last ~20 lines of /tmp/prepare-output.log>
\`\`\`

> ℹ️ This may be caused by FK constraints preventing migration on databases with real data.
```

4. **Report the failure to the user** as normal — do NOT silently swallow the error, and do NOT proceed to Step 4.

#### If prepare.sh succeeds

Proceed to Step 5 as normal. No Slack notification is sent.

### Step 5: Start Dev Server in Background

After `prepare.sh` completes successfully, start the dev server using Bash tool with `run_in_background: true` parameter.

**Important**: Use `tee` to write output to a persistent log file so `/dev-logs` works even after context compaction. The log file is the primary way `/dev-logs` reads output.

If `--tunnel-hostname=<fqdn>` was provided in args, pass it as `TUNNEL_HOSTNAME` env var:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/turbo" && TUNNEL_HOSTNAME=<fqdn> pnpm dev 2>&1 | tee "$PROJECT_ROOT/turbo/.dev-server.log"
```

Otherwise (default):

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT/turbo" && pnpm dev 2>&1 | tee "$PROJECT_ROOT/turbo/.dev-server.log"
```

**Save the dev server task_id** to a local file for TaskOutput fallback:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
echo "<dev-task_id>" > "$PROJECT_ROOT/turbo/.dev-task-id"
```

### Step 6: Display Results

Once the server is confirmed running, display the URLs:

```
✅ Dev server started in background
🔧 Runner deployment started in background (takes several minutes)

- Web:      https://www.vm7.ai:8443
- App:      https://app.vm7.ai:8443
- Docs:     https://docs.vm7.ai:8443

The app is usable now. Chat/agent features will become available once the runner finishes initializing.

Next steps:
- Use `/dev-logs` to view server output
- Use `/dev-logs [pattern]` to filter logs (e.g., `/dev-logs error`)
- Use `/dev-stop` to stop the server
```

## Notes

- Use TaskOutput with the task_id from `run_in_background` to check server output
- This operation runs in main context so the background task persists throughout the conversation
- **NEVER use `nohup` to start the server** (e.g., `nohup pnpm dev > /tmp/dev-server.log 2>&1 &`). Always use the Bash tool's `run_in_background: true` parameter instead.
