#!/bin/bash
# PR Status — check PR conflict/CI/review status in parallel
# Usage:
#   scripts/pr-status.sh <pr-number>
#
# Output: JSON with classified status:
#   "merged" | "conflict" | "ci_failing" | "no_review" | "ci_running_reviewed" | "ci_passed"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

[[ $# -lt 1 ]] && { echo "Usage: $0 <pr-number>" >&2; exit 1; }

PR="$1"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Run 3 queries in parallel
gh pr view "$PR" --repo "$REPO" --json state,mergeable,headRefOid \
  > "$WORK_DIR/pr_view.json" &

gh pr checks "$PR" --repo "$REPO" --json name,state,bucket \
  > "$WORK_DIR/pr_checks.json" &

gh api "repos/$REPO/issues/$PR/comments" \
  --jq '[.[] | select(.body | test("## Code Review"))]' \
  > "$WORK_DIR/reviews.json" &

wait

# Parse results
STATE=$(jq -r '.state' "$WORK_DIR/pr_view.json")
MERGEABLE=$(jq -r '.mergeable' "$WORK_DIR/pr_view.json")
HEAD_SHA=$(jq -r '.headRefOid' "$WORK_DIR/pr_view.json")
HEAD_SHORT="${HEAD_SHA:0:7}"

# CI analysis — use state field (SUCCESS/FAILURE/IN_PROGRESS/SKIPPED) and bucket (pass/fail/pending/skipping)
HAS_FAILURE=$(jq '[.[] | select(.state == "FAILURE")] | length > 0' "$WORK_DIR/pr_checks.json")
FAILED_JOBS=$(jq '[.[] | select(.state == "FAILURE") | .name]' "$WORK_DIR/pr_checks.json")
PENDING_JOBS=$(jq '[.[] | select(.bucket == "pending") | .name]' "$WORK_DIR/pr_checks.json")
ALL_PASSED=$(jq '[.[] | select(.state != "SUCCESS" and .state != "SKIPPED")] | length == 0' "$WORK_DIR/pr_checks.json")

# Review analysis — check if review exists for current HEAD
HAS_REVIEW=$(jq --arg sha "$HEAD_SHORT" \
  '[.[] | select(.body | test($sha))] | length > 0' "$WORK_DIR/reviews.json")
REVIEW_IDS=$(jq '[.[].id]' "$WORK_DIR/reviews.json")

# Classify status
if [[ "$STATE" == "MERGED" ]]; then
  STATUS="merged"
elif [[ "$MERGEABLE" == "CONFLICTING" ]]; then
  STATUS="conflict"
elif [[ "$HAS_FAILURE" == "true" ]]; then
  STATUS="ci_failing"
elif [[ "$HAS_REVIEW" == "false" ]]; then
  STATUS="no_review"
elif [[ "$ALL_PASSED" == "true" ]]; then
  STATUS="ci_passed"
else
  STATUS="ci_running_reviewed"
fi

jq -n \
  --argjson number "$PR" \
  --arg status "$STATUS" \
  --arg mergeable "$MERGEABLE" \
  --arg head_sha "$HEAD_SHORT" \
  --argjson has_failure "$HAS_FAILURE" \
  --argjson failed_jobs "$FAILED_JOBS" \
  --argjson pending_jobs "$PENDING_JOBS" \
  --argjson all_passed "$ALL_PASSED" \
  --argjson has_review "$HAS_REVIEW" \
  --argjson review_ids "$REVIEW_IDS" \
  '{
    number: $number,
    status: $status,
    mergeable: $mergeable,
    head_sha: $head_sha,
    ci: {
      has_failure: $has_failure,
      failed_jobs: $failed_jobs,
      pending_jobs: $pending_jobs,
      all_passed: $all_passed
    },
    review: {
      has_review_for_head: $has_review,
      review_comment_ids: $review_ids
    }
  }'
