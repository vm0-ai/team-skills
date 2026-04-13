#!/bin/bash
# PR Prompt — generate action prompt for a PR based on its current status
# Usage:
#   scripts/pr-prompt.sh <pr-number>
#
# Output: action prompt for the LLM (stdout)
# Exit 0: prompt generated (action needed)
# Exit 1: no action needed (fall through)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

[[ $# -lt 1 ]] && { echo "Usage: $0 <pr-number>" >&2; exit 2; }

PR_NUMBER="$1"
BRANCH=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json headRefName --jq '.headRefName')
CONTENT_DIR="/tmp/coding-worker"

mkdir -p "$CONTENT_DIR/prs"

# Check if a GitHub user is trusted (@vm0.ai email or vm0-related login)
is_trusted_user() {
  local login="$1"
  if [[ "$login" == "vm0-bot" ]] || [[ "$login" == *"vm0"* ]]; then
    return 0
  fi
  local email
  email=$(gh api "users/${login}" --jq '.email // empty' 2>/dev/null || true)
  if [[ "$email" == *"@vm0.ai" ]]; then
    return 0
  fi
  return 1
}

# Download PR content with security filtering
# Writes to $CONTENT_DIR/prs/<number>.md
download_pr_content() {
  local number="$1"
  local outfile="$CONTENT_DIR/prs/${number}.md"

  local pr_json
  pr_json=$(gh pr view "$number" --repo "$REPO" --json title,body,author,headRefName)
  local title author_login body branch
  title=$(echo "$pr_json" | jq -r '.title')
  author_login=$(echo "$pr_json" | jq -r '.author.login')
  body=$(echo "$pr_json" | jq -r '.body // empty')
  branch=$(echo "$pr_json" | jq -r '.headRefName')

  {
    echo "# PR #${number}: ${title}"
    echo ""
    echo "Author: ${author_login}"
    echo "Branch: ${branch}"
    echo ""
    echo "## Description"
    echo ""
    echo "$body"
    echo ""
  } > "$outfile"

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

  local review_comments
  review_comments=$(gh api "repos/${REPO}/pulls/${number}/comments" \
    --jq '[.[] | select(.user.login as $u | ($u == "vm0-bot" or ($u | test("vm0"))))] | .[] | "### Review by \(.user.login) on \(.path)\n\n\(.body)\n"' 2>/dev/null || true)

  if [ -n "$review_comments" ]; then
    {
      echo "## Review Comments (trusted only)"
      echo ""
      echo "$review_comments"
    } >> "$outfile"
  fi
}

PR_STATUS_JSON=$("$SCRIPT_DIR/pr-status.sh" "$PR_NUMBER")
STATUS=$(echo "$PR_STATUS_JSON" | jq -r '.status')

case "$STATUS" in
  merged)
    exit 1
    ;;

  conflict)
    cat <<EOF
Spawn a subagent to resolve merge conflicts on PR #${PR_NUMBER} (branch: ${BRANCH}).

Steps:
1. gh pr merge --disable-auto ${PR_NUMBER}
2. git checkout ${BRANCH}
3. git fetch origin main && git merge origin/main
4. Resolve conflicts — typically additive, keep both sides, sort alphabetically
5. git add <resolved files> && git commit -m "chore: resolve merge conflict with main"
6. git push
7. git checkout main && git pull

Note: Do not merge in the same iteration after pushing. Wait for CI to pass in the next iteration.
EOF
    exit 0
    ;;

  ci_failing)
    FAILED_JOBS=$(echo "$PR_STATUS_JSON" | jq -r '.ci.failed_jobs | join(", ")')
    download_pr_content "$PR_NUMBER" || true
    cat <<EOF
Spawn a subagent to fix CI failures on PR #${PR_NUMBER} (branch: ${BRANCH}).

Failed jobs: ${FAILED_JOBS}
PR details: ${CONTENT_DIR}/prs/${PR_NUMBER}.md

Rules:
- If runner/e2e failure: Use Slack MCP (slack_send_message, channelId: C0ALXC1SHHN) to post the failed job URL. Do not @ anyone.
- If flaky test (failure unrelated to PR changes): Report via Slack MCP to channelId C0ALXC1SHHN (include test name, failure message, job URL, PR number), then run gh run rerun <RUN_ID> --failed. Do not attempt to fix flaky tests.
- If lint/type/build failure: git checkout ${BRANCH}, fix the code, push.

When done: git checkout main && git pull
EOF
    exit 0
    ;;

  no_review)
    # Delete old review comments and run fresh review
    echo "$PR_STATUS_JSON" | jq -r '.review.review_comment_ids[]' 2>/dev/null | \
      while read -r id; do
        gh api -X DELETE "repos/${REPO}/issues/comments/$id" 2>/dev/null || true
      done

    cat <<EOF
Spawn a subagent to review and fix PR #${PR_NUMBER} (branch: ${BRANCH}).

Steps:
1. Run /github-workflow:pr-review ${PR_NUMBER}
2. If no P0/P1 issues: gh pr merge ${PR_NUMBER} --merge --auto, git checkout main && git pull. Stop.
3. git checkout ${BRANCH}, fix all P0/P1 issues
4. Run pre-commit checks: cd turbo && pnpm format && pnpm turbo run lint && pnpm check-types && pnpm vitest
5. Commit and push, then git checkout main && git pull
EOF
    exit 0
    ;;

  ci_running_reviewed)
    REVIEW_JSON=$(gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" \
      --jq '[.[] | select(.body | test("## Code Review"))] | last // empty' 2>/dev/null || echo "")
    REVIEW_BODY=$(echo "$REVIEW_JSON" | jq -r '.body // ""')

    if echo "$REVIEW_BODY" | grep -q 'Changes Requested'; then
      REVIEW_COMMENT_ID=$(echo "$REVIEW_JSON" | jq -r '.id')
      REVIEW_URL="https://github.com/${REPO}/pull/${PR_NUMBER}#issuecomment-${REVIEW_COMMENT_ID}"
      cat <<EOF
Spawn a subagent to fix review findings on PR #${PR_NUMBER} (branch: ${BRANCH}).

Review comment: ${REVIEW_URL}

Steps:
1. git checkout ${BRANCH}
2. Read the review comment above and fix all P0/P1 issues
3. Run pre-commit checks: cd turbo && pnpm format && pnpm turbo run lint && pnpm check-types && pnpm vitest
4. Commit and push, then git checkout main && git pull
EOF
      exit 0
    fi
    # LGTM — no action needed
    exit 1
    ;;

  ci_passed)
    EJECTION=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/timeline" --paginate \
      --jq '[.[] | select(.event == "removed_from_merge_queue")] | last // empty' 2>/dev/null || true)

    if [ -n "$EJECTION" ]; then
      EJECTION_REASON=$(echo "$EJECTION" | jq -r '.reason // "unknown"')
      EJECTION_TIME=$(echo "$EJECTION" | jq -r '.created_at // "unknown"')
      cat <<EOF
PR #${PR_NUMBER} (branch: ${BRANCH}) was ejected from the merge queue.

Ejection reason: ${EJECTION_REASON}
Ejection time: ${EJECTION_TIME}

Investigate the ejection before re-enqueueing:

1. If MERGE_CONFLICT: git checkout ${BRANCH} && git fetch origin main && git merge origin/main, resolve conflicts, push, then git checkout main && git pull
2. If CI_FAILURE: Check the merge queue build logs — gh run list --branch 'gh-readonly-queue/main/pr-${PR_NUMBER}-*' --status failure -L 1, then gh run view <run-id> --log-failed | tail -50. Fix real failures or rerun if flaky.
3. If DEQUEUED: Another PR in the group failed — safe to re-enqueue directly: gh pr merge ${PR_NUMBER} --repo ${REPO} --merge --auto
4. If unknown: Check PR timeline for details — gh api repos/${REPO}/pulls/${PR_NUMBER}/timeline --paginate | jq '[.[] | select(.event == "removed_from_merge_queue")]'

After resolving: git checkout main && git pull
EOF
      exit 0
    fi

    REVIEW_JSON=$(gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" \
      --jq '[.[] | select(.body | test("## Code Review"))] | last // empty' 2>/dev/null || echo "")
    REVIEW_BODY=$(echo "$REVIEW_JSON" | jq -r '.body // ""')

    if echo "$REVIEW_BODY" | grep -q 'Changes Requested'; then
      REVIEW_COMMENT_ID=$(echo "$REVIEW_JSON" | jq -r '.id')
      REVIEW_URL="https://github.com/${REPO}/pull/${PR_NUMBER}#issuecomment-${REVIEW_COMMENT_ID}"
      cat <<EOF
Spawn a subagent to fix review findings on PR #${PR_NUMBER} (branch: ${BRANCH}).

CI has passed but the review requested changes.
Review comment: ${REVIEW_URL}

Steps:
1. git checkout ${BRANCH}
2. Read the review comment above and fix all P0/P1 issues
3. Run pre-commit checks: cd turbo && pnpm format && pnpm turbo run lint && pnpm check-types && pnpm vitest
4. Commit and push, then git checkout main && git pull
EOF
      exit 0
    elif echo "$REVIEW_BODY" | grep -q 'LGTM'; then
      gh pr merge "$PR_NUMBER" --repo "$REPO" --merge --auto 2>/dev/null || true
      exit 1
    else
      cat <<EOF
Spawn a subagent to review PR #${PR_NUMBER} (branch: ${BRANCH}).

CI has passed but no clear review verdict was found.

Steps:
1. Run /github-workflow:pr-review ${PR_NUMBER}
2. If no P0/P1 issues: gh pr merge ${PR_NUMBER} --merge --auto, git checkout main && git pull. Stop.
3. git checkout ${BRANCH}, fix all P0/P1 issues
4. Run pre-commit checks: cd turbo && pnpm format && pnpm turbo run lint && pnpm check-types && pnpm vitest
5. Commit and push, then git checkout main && git pull
EOF
      exit 0
    fi
    ;;
esac

exit 1
