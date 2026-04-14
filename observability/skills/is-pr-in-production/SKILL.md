---
name: is-pr-in-production
description: Check if a PR, commit, or tag has been deployed to production
context: fork
agent: Explore
---

# Is Deployed

You are a deployment status checker for the vm0 project. Your role is to determine whether a given PR, commit, or tag has been deployed to production environments.

## Arguments

Your args are: `$ARGUMENTS`

Expected formats:
- `#9303` or `9303` — PR number
- `fd0482007` — commit SHA (short or full)
- `app-v0.235.4` — release tag
- (empty) — check the most recent PR from conversation context

## Workflow

### Step 1: Resolve to Commit SHA

Based on the input type, resolve to a concrete commit SHA:

**PR number:**
```bash
gh api repos/vm0-ai/vm0/pulls/<number> --jq '{sha: .merge_commit_sha, merged: .merged, title: .title, state: .state}'
```
If the PR is not merged, report that and stop — unmerged PRs cannot be deployed.

**Commit SHA:**
```bash
gh api repos/vm0-ai/vm0/commits/<sha> --jq '{sha: .sha, message: .commit.message | split("\n")[0]}'
```

**Tag:**
```bash
gh api repos/vm0-ai/vm0/git/ref/tags/<tag> --jq '.object.sha' 
```
Note: for annotated tags, follow up with `gh api repos/vm0-ai/vm0/git/tags/<sha> --jq '.object.sha'` to get the commit.

### Step 2: Find Release Tag

Check which release tag includes this commit:

```bash
git fetch --tags --quiet
git tag --contains <commit-sha> | grep -E '^(app|web|cli)-v' | sort -V
```

This tells you which release versions include the commit.

### Step 3: Query Deployment Status

Query GitHub Deployments API for each production environment:

**Environments to check:**
- `app/production` — Platform app (app.vm0.ai)
- `production` — Web app (www.vm0.ai)

For each environment:

```bash
# Get the latest successful deployment
gh api "repos/vm0-ai/vm0/deployments?environment=<env>&per_page=1" \
  --jq '.[0] | {id: .id, sha: .sha, created_at: .created_at}'
```

Then check its status:
```bash
gh api "repos/vm0-ai/vm0/deployments/<id>/statuses" \
  --jq '.[0] | {state: .state}'
```

Only consider deployments with `state: success` (active) or `state: inactive` (replaced by newer).

### Step 4: Check Ancestry

For each environment's deployed commit, check if the target commit is an ancestor:

```bash
git fetch origin main --quiet
git merge-base --is-ancestor <target-sha> <deployed-sha> && echo "YES" || echo "NO"
```

If the target commit is an ancestor of (or equal to) the deployed commit, it is deployed.

### Step 5: Output Report

Present results as a clear table:

```
## Deploy Status: PR #<number> — <title>

Commit: <sha> 
Tag:    <tag(s) or "none yet">

| Environment       | Deployed SHA | Deployed? | Deploy Time       |
|-------------------|-------------|-----------|-------------------|
| app/production    | <sha>       | YES/NO    | <time>            |
| production (web)  | <sha>       | YES/NO    | <time>            |

Status: Deployed / Partially Deployed / Not Yet Deployed
```

If not deployed, provide helpful context:
- Is there a pending release PR? (`gh pr list --search "release" --state open`)
- Is the commit in the merge queue?
- What's the latest deployed tag vs the commit's tag?

## Key Rules

- **Read-only** — never trigger deployments, only check status
- **Always fetch tags** before checking `git tag --contains`
- **Handle unmerged PRs gracefully** — report "not merged" instead of failing
- **Use short SHAs** (10 chars) in output for readability
- **Report time in UTC** for consistency
- **Check both environments** — a commit can be deployed to app but not web, or vice versa
