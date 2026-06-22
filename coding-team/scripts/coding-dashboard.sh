#!/bin/bash
# Coding Dashboard — consolidated view of CI, merge queue, and recent merges
# Usage:
#   scripts/coding-dashboard.sh
#
# Output: formatted text dashboard

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  NC=$'\033[0m'
else
  GREEN=""
  YELLOW=""
  NC=""
fi

ME=$(gh api user --jq '.login')
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# --- Parallel data gathering ---

"$SCRIPT_DIR/pipeline-status.sh" > "$WORK_DIR/pipeline.json" &
PID_PIPELINE=$!

gh issue list --repo "$REPO" --assignee "$ME" --state open \
  --json number,title,labels,closedByPullRequestsReferences --limit 50 \
  > "$WORK_DIR/issues_assignee.json" 2>/dev/null &
PID_ISSUES_A=$!

gh issue list --repo "$REPO" --author "$ME" --state open \
  --json number,title,labels,closedByPullRequestsReferences,assignees --limit 50 \
  > "$WORK_DIR/issues_author.json" 2>/dev/null &
PID_ISSUES_U=$!

gh pr list --repo "$REPO" --author "$ME" --state open \
  --json number,title,labels,mergeable,headRefOid,headRefName --limit 50 \
  > "$WORK_DIR/prs_author.json" 2>/dev/null &
PID_PRS_A=$!

gh pr list --repo "$REPO" --assignee "$ME" --state open \
  --json number,title,labels,mergeable,headRefOid,headRefName --limit 50 \
  > "$WORK_DIR/prs_assignee.json" 2>/dev/null &
PID_PRS_S=$!

gh pr list --repo "$REPO" --author "$ME" --state merged \
  --json number,title,mergedAt --limit 30 \
  > "$WORK_DIR/merged_author.json" 2>/dev/null &
PID_MERGED_A=$!

gh pr list --repo "$REPO" --assignee "$ME" --state merged \
  --json number,title,mergedAt --limit 30 \
  > "$WORK_DIR/merged_assignee.json" 2>/dev/null &
PID_MERGED_S=$!

# Wait for all jobs
ERRORS=()
wait "$PID_PIPELINE" || ERRORS+=("pipeline-status.sh failed")
wait "$PID_ISSUES_A" || ERRORS+=("issues (assignee) fetch failed")
wait "$PID_ISSUES_U" || ERRORS+=("issues (author) fetch failed")
wait "$PID_PRS_A" || ERRORS+=("PRs (author) fetch failed")
wait "$PID_PRS_S" || ERRORS+=("PRs (assignee) fetch failed")
wait "$PID_MERGED_A" || ERRORS+=("merged PRs (author) fetch failed")
wait "$PID_MERGED_S" || ERRORS+=("merged PRs (assignee) fetch failed")

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Warning: some background jobs failed:" >&2
  for err in "${ERRORS[@]}"; do
    echo "  - $err" >&2
  done
fi

# Validate critical JSON files before rendering
if [[ ! -s "$WORK_DIR/pipeline.json" ]] || ! jq empty "$WORK_DIR/pipeline.json" 2>/dev/null; then
  echo "Error: failed to fetch pipeline data" >&2
  exit 1
fi

# Build open items: deduplicate issues/PRs across author+assignee queries
OPEN_ITEMS=$(jq -rs '
  ([.[0][], (.[1][] | select(.assignees | length == 0))] | group_by(.number) | map(.[0])
   | map({
       number, title,
       pending: ([.labels[].name] | any(. == "pending")),
       linked_prs: [.closedByPullRequestsReferences[].number]
     }) | sort_by(.number)) as $issues |
  ([.[2][], .[3][]] | group_by(.number) | map(.[0])
   | map({
       number, title,
       pending: ([.labels[].name] | any(. == "pending")),
       mergeable, head: (.headRefOid[:7]), branch: .headRefName
     }) | sort_by(.number)) as $prs |
  {issues: $issues, prs: $prs,
   issue_count: ($issues | length), pr_count: ($prs | length)}
' "$WORK_DIR/issues_assignee.json" \
  "$WORK_DIR/issues_author.json" \
  "$WORK_DIR/prs_author.json" \
  "$WORK_DIR/prs_assignee.json")

# Combine and deduplicate merged PRs
jq -rs 'add | unique_by(.number) | sort_by(.mergedAt) | reverse | .[0:20]' \
  "$WORK_DIR/merged_author.json" "$WORK_DIR/merged_assignee.json" \
  > "$WORK_DIR/merged.json" 2>/dev/null || echo "[]" > "$WORK_DIR/merged.json"

# --- Render ---

OUTPUT_FILE="$WORK_DIR/output.txt"
exec 3>&1
exec > "$OUTPUT_FILE"

echo "📊 CI Pipeline - Turbo"

CI_LINE=$(jq -r '
  [.ci_runs[] | if .conclusion == "success" then "✅" elif .conclusion == "failure" then "🔴" else "⏳" end]
  | join("")
' "$WORK_DIR/pipeline.json")
MG_LINE=$(jq -r '
  [.merge_group_runs[] | if .conclusion == "success" then "✅" elif .conclusion == "failure" then "🔴" else "⏳" end]
  | join("")
' "$WORK_DIR/pipeline.json")
echo "  main         $CI_LINE"
echo "  merge_group  $MG_LINE"

# Find most recent failure on main
FAILURE_INFO=$(jq -r '
  .ci_runs | to_entries
  | map(select(.value.conclusion == "failure"))
  | if length == 0 then "none"
    else .[0] | "\(.key + 1)|\(.value.url)|\(.value.created_at)"
    end
' "$WORK_DIR/pipeline.json")

if [[ "$FAILURE_INFO" == "none" ]]; then
  echo ""
  echo "  main: no failures"
else
  IFS='|' read -r FAIL_POS FAIL_URL FAIL_TIME <<< "$FAILURE_INFO"
  SUCCESS_SINCE=$((FAIL_POS - 1))

  if command -v gdate &>/dev/null; then
    DATE_CMD="gdate"
  else
    DATE_CMD="date"
  fi
  FAIL_EPOCH=$($DATE_CMD -d "$FAIL_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$FAIL_TIME" +%s 2>/dev/null || echo 0)

  if [[ "$FAIL_EPOCH" == "0" ]]; then
    ELAPSED_STR="unknown"
  else
    NOW_EPOCH=$($DATE_CMD +%s)
    DIFF_SECS=$((NOW_EPOCH - FAIL_EPOCH))
    DIFF_HOURS=$((DIFF_SECS / 3600))
    DIFF_MINS=$(( (DIFF_SECS % 3600) / 60 ))
    ELAPSED_STR="${DIFF_HOURS}h ${DIFF_MINS}m"
  fi

  echo ""
  echo "  main: last failure #${FAIL_POS}/30 (${ELAPSED_STR} ago, ${SUCCESS_SINCE} successes since)"
  echo "    Run: ${FAIL_URL}"

  RUN_ID=$(echo "$FAIL_URL" | grep -oE '[0-9]+$')
  FAILED_JOBS=$(gh run view "$RUN_ID" --repo "$REPO" --json jobs --jq '[.jobs[] | select(.conclusion == "failure") | .name] | join(", ")' 2>/dev/null || echo "unknown")
  echo "    Failed jobs: ${FAILED_JOBS}"
fi

# --- Render: Merge Queue ---

echo ""
echo "🚦 Merge Queue"

QUEUE_COUNT=$(jq '.merge_queue | length' "$WORK_DIR/pipeline.json")
if [[ "$QUEUE_COUNT" == "0" ]]; then
  echo "  (empty)"
else
  jq -r '
    .merge_queue[] |
    (if .ci_state == "SUCCESS" then "✅"
     elif .ci_state == "FAILURE" or .ci_state == "ERROR" then "🔴"
     else "⏳" end) as $emoji |
    "- \($emoji) #\(.number) — \(.title) (\(.author))"
  ' "$WORK_DIR/pipeline.json"
fi

# --- Render: Release Status ---

RELEASE_NULL=$(jq '.release == null' "$WORK_DIR/pipeline.json")
if [[ "$RELEASE_NULL" == "false" ]]; then
  echo ""
  echo "📦 Release Status"

  HAS_PR=$(jq '.release.open_pr != null' "$WORK_DIR/pipeline.json")
  if [[ "$HAS_PR" == "true" ]]; then
    PR_NUM=$(jq '.release.open_pr.number' "$WORK_DIR/pipeline.json")
    echo "  Open PR: #${PR_NUM}"
    jq -r '.release.open_pr.changes[]? | gsub("\\[(?<x>[^]]+)\\]\\([^)]+\\)"; .x) | gsub(", closes #[0-9]+"; "") | "  - \(.)"' "$WORK_DIR/pipeline.json"
  fi

  HAS_RUN=$(jq '.release.in_progress_run != null' "$WORK_DIR/pipeline.json")
  if [[ "$HAS_RUN" == "true" ]]; then
    echo ""
    echo "  🚀 Release in progress"
  fi
fi

# --- Render: Open Items ---

echo ""
echo "📋 Open Items"

MQ_NUMBERS=$(jq '[.merge_queue[].number]' "$WORK_DIR/pipeline.json")

TOTAL=$(echo "$OPEN_ITEMS" | jq '.issue_count + .pr_count')
if [[ "$TOTAL" == "0" ]]; then
  echo "  -- idle"
else
  echo "$OPEN_ITEMS" | jq -r --argjson mq "$MQ_NUMBERS" --arg green "$GREEN" --arg yellow "$YELLOW" --arg nc "$NC" '
    ([.issues[].linked_prs[]?]) as $linked |
    ([.prs[] | {(.number | tostring): .}] | add // {}) as $pr_map |
    [
      .issues[] |
      (if ([.linked_prs[]?] | any(. as $p | $mq | any(. == $p))) then "\($green)[Queued]\($nc) "
       elif .pending then "\($yellow)[Pending]\($nc) "
       else "" end) as $marker |
      "- \($marker)Issue #\(.number) — \(.title)",
      (.linked_prs[]? as $pr_num |
        ($pr_map[$pr_num | tostring].title // null) as $pr_title |
        if $pr_title then
          "  - PR #\($pr_num) — \($pr_title)"
        else
          "  - PR #\($pr_num)"
        end)
    ] +
    [ .prs[] | select(.number as $n | $linked | any(. == $n) | not) |
      "- \(if .pending then "\($yellow)[Pending]\($nc) " else "" end)PR #\(.number) — \(.title)" ] |
    join("\n")
  '
fi

# --- Render: Recently Merged PRs ---

echo ""
echo "📝 Recently Merged (top 20)"

if [[ -s "$WORK_DIR/merged.json" ]] && [[ "$(jq 'length' "$WORK_DIR/merged.json")" -gt 0 ]]; then
  jq -r '.[] |
    (.mergedAt | split("T") | .[0] | split("-") | .[1] + "/" + .[2]) as $date |
    (.mergedAt | split("T") | .[1] | split(":") | .[0] + ":" + .[1]) as $time |
    "- \($date) \($time) #\(.number) — \(.title)"
  ' "$WORK_DIR/merged.json"
else
  echo "  (none)"
fi

exec >&3
exec 3>&-
clear
cat "$OUTPUT_FILE"
