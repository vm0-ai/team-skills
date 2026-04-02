---
name: skill-action
description: Implement changes to team-skills repo based on deep-dive research, innovation, and plan findings
context: main
---

# Skill Action

You are a skill implementer. Your role is to execute changes in the `vm0-ai/team-skills` repository based on the conclusions from prior deep-dive phases (research, innovate, plan).

## Prerequisites

This skill expects that the following phases have already been completed in this conversation:

1. **`/skill-manager:skill-research`** — research findings exist in `/tmp/deep-dive/{task-name}/research.md`
2. **`/deep-dive:deep-innovate`** — innovation findings exist in `/tmp/deep-dive/{task-name}/innovate.md`
3. **`/deep-dive:deep-plan`** — implementation plan exists in `/tmp/deep-dive/{task-name}/plan.md`

If any of these are missing, inform the user which phase(s) need to be completed first and stop.

## Arguments

Your args are: `$ARGUMENTS`

Optional. If provided, use as additional guidance for the implementation. If not provided, follow the plan as-is.

## Workflow

### Step 1: Verify Deep-Dive Outputs

Check that the deep-dive outputs exist:

```bash
ls /tmp/deep-dive/*/research.md /tmp/deep-dive/*/innovate.md /tmp/deep-dive/*/plan.md
```

Read the plan file to understand exactly what changes need to be made.

### Step 2: Verify team-skills Repository

Ensure the team-skills repo is available and clean:

```bash
cd /tmp/team-skills && git status
```

If the repo doesn't exist or is dirty, clone fresh:

```bash
cd /tmp && rm -rf team-skills && gh repo clone vm0-ai/team-skills
```

### Step 3: Implement Changes

Follow the plan from `/tmp/deep-dive/{task-name}/plan.md` to make the required changes in `/tmp/team-skills/`.

Apply changes file by file, following the plan's step order.

### Step 4: Review Changes

Show the full diff for user review:

```bash
cd /tmp/team-skills && git diff --stat && git diff
```

Also show any new untracked files:

```bash
cd /tmp/team-skills && git status
```

Ask the user to confirm before proceeding to commit.

### Step 5: Commit and Push

After user confirmation:

```bash
cd /tmp/team-skills
git add -A
git commit -m "<conventional commit message based on changes>"
git push origin main
```

Use a conventional commit message that accurately describes the changes (e.g., `feat(plugin-name): add new-skill skill`).

### Step 6: Sync Local Cache

Update the local marketplace and cache for any changed plugins:

```bash
cd /home/vscode/.config/claude/plugins/marketplaces/team-skills && git pull
```

For each plugin that was modified:

```bash
rm -rf /home/vscode/.config/claude/plugins/cache/team-skills/<plugin-name>
mkdir -p /home/vscode/.config/claude/plugins/cache/team-skills/<plugin-name>/1.0.0
cp -r /home/vscode/.config/claude/plugins/marketplaces/team-skills/<plugin-name>/* \
  /home/vscode/.config/claude/plugins/cache/team-skills/<plugin-name>/1.0.0/
```

### Step 7: Report

Output a summary of what was done:

```
Changes pushed to vm0-ai/team-skills

Commit: <commit hash> <commit message>
Files changed: <count>

Modified plugins synced to local cache.
Start a new conversation to use updated skills.
```

## Key Rules

- **Never implement without a plan** — all three deep-dive phases must be completed first
- **Always show diff before committing** — wait for user confirmation
- **Use conventional commits** — follow the `type(scope): description` format
- **Sync local cache** — update marketplace and cache after push so changes are available immediately
- **Follow the plan** — do not deviate from the plan unless the user provides additional guidance via args
