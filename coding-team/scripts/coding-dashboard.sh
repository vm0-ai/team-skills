#!/bin/bash
# Coding Dashboard — consolidated view of CI, merge queue, lanes, and recent merges
# Usage:
#   scripts/coding-dashboard.sh [max_workers]
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

MAX_WORKERS="${1:-4}"
ME=$(gh api user --jq '.login')
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# --- Parallel data gathering ---

FIRST_LANE=$(printf "vm%02d" 1)
LAST_LANE=$(printf "vm%02d" "$MAX_WORKERS")

"$SCRIPT_DIR/pipeline-status.sh" > "$WORK_DIR/pipeline.json" &
PID_PIPELINE=$!

"$SCRIPT_DIR/lane-status.sh" "${FIRST_LANE}-${LAST_LANE}" --user "$ME" > "$WORK_DIR/lanes_vm.json" &
PID_LANES_VM=$!

"$SCRIPT_DIR/lane-status.sh" "zero" --user "$ME" > "$WORK_DIR/lanes_zero.json" &
PID_LANES_ZERO=$!

# Merged PRs across all lanes (per-lane files to avoid interleaved writes)
MERGED_PIDS=()
for i in $(seq 1 "$MAX_WORKERS"); do
  LANE=$(printf "vm%02d" "$i")
  gh pr list --repo "$REPO" --label "$LANE" --state merged \
    --json number,title,mergedAt,labels,author,assignees --limit 20 \
    --jq ".[] | select(.author.login == \"$ME\" or (.assignees | map(.login) | any(. == \"$ME\"))) | {number, title, mergedAt, lane: \"$LANE\"}" \
    > "$WORK_DIR/merged_${LANE}.jsonl" 2>"$WORK_DIR/merged_${LANE}.err" &
  MERGED_PIDS+=($!)
done

# Merged PRs for the "zero" lane
gh pr list --repo "$REPO" --label "zero" --state merged \
  --json number,title,mergedAt,labels,author,assignees --limit 20 \
  --jq ".[] | select(.author.login == \"$ME\" or (.assignees | map(.login) | any(. == \"$ME\"))) | {number, title, mergedAt, lane: \"zero\"}" \
  > "$WORK_DIR/merged_zero.jsonl" 2>"$WORK_DIR/merged_zero.err" &
MERGED_PIDS+=($!)

# Merged PRs with no lane label (unlaned)
gh pr list --repo "$REPO" --author "$ME" --state merged \
  --json number,title,mergedAt,labels --limit 30 \
  --jq '.[] | select([.labels[].name] | map(test("^(vm[0-9]+|zero)$")) | any | not) | {number, title, mergedAt, lane: "unlaned"}' \
  > "$WORK_DIR/merged_unlaned_author.jsonl" 2>/dev/null &
MERGED_PIDS+=($!)

gh pr list --repo "$REPO" --assignee "$ME" --state merged \
  --json number,title,mergedAt,labels --limit 30 \
  --jq '.[] | select([.labels[].name] | map(test("^(vm[0-9]+|zero)$")) | any | not) | {number, title, mergedAt, lane: "unlaned"}' \
  > "$WORK_DIR/merged_unlaned_assignee.jsonl" 2>/dev/null &
MERGED_PIDS+=($!)

# Open issues/PRs not filtered by lane (for unlaned section)
gh issue list --repo "$REPO" --assignee "$ME" --state open \
  --json number,title,labels,closedByPullRequestsReferences --limit 50 \
  > "$WORK_DIR/unlaned_issues_assignee.json" 2>/dev/null &
PID_UNLANED_IA=$!

gh issue list --repo "$REPO" --author "$ME" --state open \
  --json number,title,labels,closedByPullRequestsReferences,assignees --limit 50 \
  > "$WORK_DIR/unlaned_issues_author.json" 2>/dev/null &
PID_UNLANED_IU=$!

gh pr list --repo "$REPO" --author "$ME" --state open \
  --json number,title,labels,mergeable,headRefOid,headRefName --limit 50 \
  > "$WORK_DIR/unlaned_prs_author.json" 2>/dev/null &
PID_UNLANED_PA=$!

gh pr list --repo "$REPO" --assignee "$ME" --state open \
  --json number,title,labels,mergeable,headRefOid,headRefName --limit 50 \
  > "$WORK_DIR/unlaned_prs_assignee.json" 2>/dev/null &
PID_UNLANED_PS=$!

# Wait for critical jobs and check exit status
ERRORS=()
wait "$PID_PIPELINE" || ERRORS+=("pipeline-status.sh failed")
wait "$PID_LANES_VM" || ERRORS+=("lane-status.sh failed")
wait "$PID_LANES_ZERO" || ERRORS+=("lane-status.sh zero failed")
for pid in "${MERGED_PIDS[@]}"; do
  wait "$pid" || ERRORS+=("merged PR fetch (pid $pid) failed")
done
wait "$PID_UNLANED_IA" || ERRORS+=("unlaned issues (assignee) fetch failed")
wait "$PID_UNLANED_IU" || ERRORS+=("unlaned issues (author) fetch failed")
wait "$PID_UNLANED_PA" || ERRORS+=("unlaned PRs (author) fetch failed")
wait "$PID_UNLANED_PS" || ERRORS+=("unlaned PRs (assignee) fetch failed")

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
if [[ ! -s "$WORK_DIR/lanes_vm.json" ]] || ! jq empty "$WORK_DIR/lanes_vm.json" 2>/dev/null; then
  echo "Error: failed to fetch lane data" >&2
  exit 1
fi

# Merge vm lanes + zero lane into a single lanes.json
if [[ -s "$WORK_DIR/lanes_zero.json" ]] && jq empty "$WORK_DIR/lanes_zero.json" 2>/dev/null; then
  jq -s '.[0] + .[1]' "$WORK_DIR/lanes_vm.json" "$WORK_DIR/lanes_zero.json" > "$WORK_DIR/lanes.json"
else
  cp "$WORK_DIR/lanes_vm.json" "$WORK_DIR/lanes.json"
fi

# Build unlaned lane object: open issues/PRs for $ME with no lane label
UNLANED_LANE=$(jq -rs --argjson max "$MAX_WORKERS" '
  (["zero"] + [range(1; $max+1) | . as $i | "vm" + (if $i < 10 then "0" else "" end) + ($i | tostring)]) as $lane_labels |
  ([.[0][], (.[1][] | select(.assignees | length == 0))] | group_by(.number) | map(.[0])
   | map(select([.labels[].name] | any(. as $l | $lane_labels | any(. == $l)) | not))
   | map({
       number, title,
       pending: ([.labels[].name] | any(. == "pending")),
       linked_prs: [.closedByPullRequestsReferences[].number]
     }) | sort_by(.number)) as $issues |
  ([.[2][], .[3][]] | group_by(.number) | map(.[0])
   | map(select([.labels[].name] | any(. as $l | $lane_labels | any(. == $l)) | not))
   | map({
       number, title,
       pending: ([.labels[].name] | any(. == "pending")),
       mergeable, head: (.headRefOid[:7]), branch: .headRefName
     }) | sort_by(.number)) as $prs |
  {
    lane: "unlaned",
    issues: $issues, prs: $prs,
    issue_count: ($issues | length), pr_count: ($prs | length),
    total: (($issues | length) + ($prs | length))
  }
' "$WORK_DIR/unlaned_issues_assignee.json" \
  "$WORK_DIR/unlaned_issues_author.json" \
  "$WORK_DIR/unlaned_prs_author.json" \
  "$WORK_DIR/unlaned_prs_assignee.json")

if [[ "$(echo "$UNLANED_LANE" | jq '.total')" -gt 0 ]]; then
  jq --argjson u "$UNLANED_LANE" '. + [$u]' "$WORK_DIR/lanes.json" > "$WORK_DIR/lanes_tmp.json"
  mv "$WORK_DIR/lanes_tmp.json" "$WORK_DIR/lanes.json"
fi

# Combine per-lane merged PR files (including zero)
cat "$WORK_DIR"/merged_vm*.jsonl "$WORK_DIR/merged_zero.jsonl" \
  "$WORK_DIR/merged_unlaned_author.jsonl" "$WORK_DIR/merged_unlaned_assignee.jsonl" \
  > "$WORK_DIR/merged_raw.jsonl" 2>/dev/null || true

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

  # Calculate time elapsed
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

  # Get failed job names
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

# --- Render: Lane Status ---

echo ""
echo "📋 Lane Status"

# Build merge queue PR number set for [Queued] markers
MQ_NUMBERS=$(jq '[.merge_queue[].number]' "$WORK_DIR/pipeline.json")

jq -r --argjson mq "$MQ_NUMBERS" --arg green "$GREEN" --arg yellow "$YELLOW" --arg nc "$NC" '
  .[] |
  "\n\(.lane)" as $header |
  if (.issue_count + .pr_count) == 0 then
    ([$header, "  -- idle"] | join("\n"))
  else
    # Collect all PR numbers linked to any issue
    ([.issues[].linked_prs[]?]) as $linked |
    # Index PRs by number for title lookup
    ([.prs[] | {(.number | tostring): .}] | add // {}) as $pr_map |
    [ $header ] +
    [
      .issues[] |
      # [Queued] if any linked PR is in merge queue
      (if ([.linked_prs[]?] | any(. as $p | $mq | any(. == $p))) then "\($green)[Queued]\($nc) "
       elif .pending then "\($yellow)[Pending]\($nc) "
       else "" end) as $marker |
      "- \($marker)Issue #\(.number) — \(.title)",
      # Show linked PRs indented under their issue
      (.linked_prs[]? as $pr_num |
        ($pr_map[$pr_num | tostring].title // null) as $pr_title |
        if $pr_title then
          "  - PR #\($pr_num) — \($pr_title)"
        else
          "  - PR #\($pr_num)"
        end)
    ] +
    # Standalone PRs (not linked to any issue)
    [ .prs[] | select(.number as $n | $linked | any(. == $n) | not) |
      "- \(if .pending then "\($yellow)[Pending]\($nc) " else "" end)PR #\(.number) — \(.title)" ] |
    join("\n")
  end
' "$WORK_DIR/lanes.json"

# --- Render: Recently Merged PRs ---

echo ""
echo "📝 Recently Merged (top 20)"

if [[ -s "$WORK_DIR/merged_raw.jsonl" ]]; then
  jq -rs 'unique_by(.number) | sort_by(.mergedAt) | reverse | .[0:20][] |
    (.mergedAt | split("T") | .[0] | split("-") | .[1] + "/" + .[2]) as $date |
    (.mergedAt | split("T") | .[1] | split(":") | .[0] + ":" + .[1]) as $time |
    "- \($date) \($time) #\(.number) \(.lane) — \(.title)"
  ' "$WORK_DIR/merged_raw.jsonl"
else
  echo "  (none)"
fi

exec >&3
exec 3>&-
clear
cat "$OUTPUT_FILE"
