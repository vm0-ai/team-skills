#!/bin/bash
# Coding Worker — deterministic decision script for the autonomous coding agent
# Usage:
#   scripts/coding-worker.sh <label>
#
# Output format:
#   First line: INTERVAL:<minutes>
#   Remaining lines: action prompt for the LLM (or "idle")
#
# The script queries GitHub state, makes all decisions, and outputs a prompt
# that /begin-coding-worker follows exactly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

LABEL="${1:?Usage: $0 <label>}"
STATE_FILE="/tmp/coding-worker-interval-${LABEL}"
CONTENT_DIR="/tmp/coding-worker"

mkdir -p "$CONTENT_DIR/issues" "$CONTENT_DIR/prs"

# --- Helper functions ---

output_action() {
  echo "1" > "$STATE_FILE"
  echo "INTERVAL:1"
}

output_idle() {
  local current=1
  if [ -f "$STATE_FILE" ]; then
    current=$(cat "$STATE_FILE")
  fi
  local next=$((current * 2))
  local max_interval=30
  local dow hour
  dow=$(TZ=Asia/Shanghai date +%u)
  hour=$(TZ=Asia/Shanghai date +%-H)
  if [ "$dow" -ge 1 ] && [ "$dow" -le 5 ] && [ "$hour" -ge 10 ] && [ "$hour" -lt 19 ]; then
    max_interval=5
  fi
  if [ "$next" -gt "$max_interval" ]; then
    next=$max_interval
  fi
  echo "$next" > "$STATE_FILE"
  echo "INTERVAL:${next}"
  echo "idle"
}

# Check if a GitHub user is trusted (@vm0.ai email or vm0-related login)
is_trusted_user() {
  local login="$1"
  # Trust vm0-bot and logins containing "vm0"
  if [[ "$login" == "vm0-bot" ]] || [[ "$login" == *"vm0"* ]]; then
    return 0
  fi
  # Check email
  local email
  email=$(gh api "users/${login}" --jq '.email // empty' 2>/dev/null || true)
  if [[ "$email" == *"@vm0.ai" ]]; then
    return 0
  fi
  return 1
}

# Download issue content with security filtering
# Writes to $CONTENT_DIR/issues/<number>.md

download_issue_content() {
  local number="$1"
  local outfile="$CONTENT_DIR/issues/${number}.md"

  # Get issue metadata
  local issue_json
  issue_json=$(gh issue view "$number" --repo "$REPO" --json title,body,author)
  local title author_login body
  title=$(echo "$issue_json" | jq -r '.title')
  author_login=$(echo "$issue_json" | jq -r '.author.login')
  body=$(echo "$issue_json" | jq -r '.body // empty')

  # Verify author is trusted
  if ! is_trusted_user "$author_login"; then
    echo "UNTRUSTED AUTHOR ($author_login) — skipped" > "$outfile"
    return 1
  fi

  # Write title and body
  {
    echo "# Issue #${number}: ${title}"
    echo ""
    echo "Author: ${author_login}"
    echo ""
    echo "## Description"
    echo ""
    echo "$body"
    echo ""
  } > "$outfile"

  # Get trusted comments
  local comments
  comments=$(gh api "repos/${REPO}/issues/${number}/comments" \
    --jq '[.[] | select(.user.login as $u | ($u == "vm0-bot" or ($u | test("vm0"))))] | .[] | "### Comment by \(.user.login)\n\n\(.body)\n"' 2>/dev/null || true)

  if [ -n "$comments" ]; then
    {
      echo "## Comments (trusted only)"
      echo ""
      echo "$comments"
    } >> "$outfile"
  fi

  return 0
}

# --- Step 0: Sync main ---

rm -f .claude/scheduled_tasks.lock
git fetch origin main >&2 2>&1
git checkout -f main >&2 2>&1
git reset --hard origin/main >&2 2>&1
git clean -df >&2 2>&1
git stash clear >&2 2>&1

# --- Phase A: Check PRs ---

LANE_DATA=$("$SCRIPT_DIR/lane-status.sh" "$LABEL")
PRS=$(echo "$LANE_DATA" | jq '[.[0].prs // [] | .[] | select(.pending | not)]')
PR_COUNT=$(echo "$PRS" | jq 'length')

if [ "$PR_COUNT" -gt 0 ]; then
  PR_NUMBER=$(echo "$PRS" | jq -r '.[0].number')

  if PR_PROMPT=$("$SCRIPT_DIR/pr-prompt.sh" "$PR_NUMBER"); then
    output_action
    echo "$PR_PROMPT"
    exit 0
  fi
fi

# --- Phase B: Implement new issue ---

NEXT_ISSUE_JSON=$("$SCRIPT_DIR/next-issue.sh" "$LABEL" || true)

if [ -n "$NEXT_ISSUE_JSON" ]; then
  ISSUE_NUMBER=$(echo "$NEXT_ISSUE_JSON" | jq -r '.number')
  ISSUE_TITLE=$(echo "$NEXT_ISSUE_JSON" | jq -r '.title')
  IS_PENDING=$(echo "$NEXT_ISSUE_JSON" | jq -r '[.labels[] | select(. == "pending")] | length > 0')

  # Download and security-filter issue content
  if download_issue_content "$ISSUE_NUMBER"; then
    output_action

    if [ "$IS_PENDING" = "true" ]; then
      cat <<EOF
Spawn a subagent to review the plan completeness for issue #${ISSUE_NUMBER}.

Issue title: ${ISSUE_TITLE}
Issue content: ${CONTENT_DIR}/issues/${ISSUE_NUMBER}.md

Check whether issue #${ISSUE_NUMBER} has a complete plan:
- If the plan includes changes to **web**, the issue must list a test plan following /testing web guidelines.
- If the plan includes changes to **turbo/apps/app**, the issue must list a test plan following /testing platform guidelines.

If the test plan is incomplete or missing:
1. Add the missing test plan to the issue based on the relevant /testing skill.
2. When done: git checkout main && git pull

If the test plan is complete and the overall plan is solid with nothing requiring human confirmation:
1. Remove the pending label: gh issue edit ${ISSUE_NUMBER} --remove-label "pending"
2. When done: git checkout main && git pull
EOF
    else
      cat <<EOF
Spawn a subagent to work on issue #${ISSUE_NUMBER}.

Issue title: ${ISSUE_TITLE}
Issue content: ${CONTENT_DIR}/issues/${ISSUE_NUMBER}.md

Check if the issue already has a plan (a comment starting with "# Plan:").

If a plan exists:
1. Run /issue-implement
2. After PR is created, add label: gh pr edit <PR_NUMBER> --add-label "${LABEL}"
3. When done: git checkout main && git pull

If no plan exists:
1. Run /issue-plan
2. When done: git checkout main && git pull
3. Do NOT run /issue-implement in this iteration. Implementation will happen in the next iteration.
EOF
    fi
    exit 0
  fi
  # If download failed (untrusted author), fall through to idle
fi

# --- Nothing to do ---

output_idle
