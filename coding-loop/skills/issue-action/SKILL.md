---
name: issue-action
description: Implement issue, review PR, and verify CI — runs issue-implement, pr-review-loop, and pr-check-loop sequentially
---

# Issue Action

You are an issue-to-PR specialist. Your role is to implement a GitHub issue, then shepherd the resulting PR through code review and CI by running three skills in sequence.

## Arguments

Your args are: `$ARGUMENTS`

Args are passed through to the issue-implement skill (typically empty — it detects the issue from conversation context).

---

## Workflow

Run these three skills **sequentially**. Each skill must complete before starting the next.

### Step 1: Implement

```
invoke skill /issue-implement
```

Implement the issue following the approved plan, create a feature branch, write code and tests, and create a Pull Request.

**If implementation exits with "pending" label** (blocked, needs clarification): Stop here. Do NOT proceed to Step 2.

Extract the PR number from the output for the next steps.

### Step 2: Review Loop

```
invoke skill /pr-review-loop <PR_NUMBER>
```

Iteratively review the PR, post findings, fix P0/P1 issues, and repeat until LGTM or max iterations.

**If review ends with "Changes Requested (max iterations)"**: Stop here. Add "pending" label to the issue and report that manual intervention is needed. Do NOT proceed to Step 3.

### Step 3: Check Loop

```
invoke skill /pr-check-loop <PR_NUMBER>
```

Monitor CI pipeline, auto-fix lint/format issues, and loop until all checks pass.

**If checks end with "Manual Fix Required" or "Timeout"**: Add "pending" label to the issue and report the failure.

---

## Completion

### All steps succeeded

Post a comment to the issue:

```bash
gh issue comment {issue-id} --body "Work completed. PR created: {pr-url}

Code review passed and all CI checks passing."
```

### Any step failed

Add "pending" label to the issue and exit:

```bash
gh issue edit {issue-id} --add-label pending
```

---

## Summary

After the workflow completes (or stops early), display:

```
Issue Action Complete

Issue: #{issue-id} - {title}
Implementation: <PR Created / Blocked>
Review:         <LGTM / Changes Requested / Skipped>
CI:             <All Passed / Failed / Skipped>
PR:             {pr-url or N/A}
```

If any step was skipped due to a prior failure, show "Skipped" for that step.
