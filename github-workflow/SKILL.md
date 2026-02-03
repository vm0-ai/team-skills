---
name: github-workflow
description: AI-assisted GitHub issue management - plan issues with deep-dive workflow, implement approved plans, create issues from conversations, and consolidate discussions.
---

# GitHub Issue Workflow

AI-assisted workflow for managing GitHub issues with structured planning and implementation.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated
- Run `gh auth status` to verify

## When to Use

- **issue-plan** - Start working on a GitHub issue with full deep-dive workflow
- **issue-action** - Continue implementation based on approved plan
- **issue-create** - Create issues from conversation context
- **issue-compact** - Consolidate issue discussion into clean body for handoff

---

# Command: issue-plan

**Usage:** `/issue-plan [issue-id]`

Start working on a GitHub issue by executing the complete deep-dive workflow.

## Workflow

### Step 1: Fetch Issue Details

```bash
gh issue view {issue-id} --json title,body,comments,labels
```

### Step 2: Check for Existing Artifacts

Look for existing work in `/tmp/deep-dive/*/`:
- `research.md` - Research phase completed
- `innovate.md` - Innovation phase completed
- `plan.md` - Plan phase completed

### Step 3: Execute Deep-Dive Workflow

Run phases automatically in sequence (no user confirmation between phases):

1. **Research Phase** - Analyze codebase, create `research.md`, post to issue
2. **Innovate Phase** - Explore solutions, create `innovate.md`, post to issue
3. **Plan Phase** - Create implementation plan, create `plan.md`, post to issue

### Step 4: Finalize

1. Add "pending" label to wait for user approval
2. Exit and wait for user to review the plan

## Posting to Issue

After each phase, post the artifact as a comment:

```bash
gh issue comment {issue-id} --body-file /tmp/deep-dive/{task-name}/research.md
gh issue comment {issue-id} --body-file /tmp/deep-dive/{task-name}/innovate.md
gh issue comment {issue-id} --body-file /tmp/deep-dive/{task-name}/plan.md
```

---

# Command: issue-action

**Usage:** `/issue-action`

Continue working on a GitHub issue from conversation context, following the approved plan.

## Workflow

### Step 1: Retrieve Context

1. Find issue ID from conversation history
2. Locate deep-dive artifacts in `/tmp/deep-dive/{task-name}/`

### Step 2: Fetch Latest Updates

```bash
gh issue view {issue-id} --json title,body,comments,labels
```

### Step 3: Remove Pending Label

```bash
gh issue edit {issue-id} --remove-label pending
```

### Step 4: Analyze Feedback

Review comments for:
- Plan approval/rejection
- Modification requests
- Additional requirements

### Step 5: Take Action

- **Plan approved** → Proceed to implementation
- **Changes requested** → Update plan, post revised, add "pending" label
- **Questions asked** → Answer in comment, add "pending" label

### Step 6: Implementation

1. Read `plan.md` for implementation steps
2. Create/switch to feature branch
3. Implement changes following plan exactly
4. Write and run tests after each change
5. Commit with conventional commit messages

### Step 7: Create PR

1. Push branch and create Pull Request
2. Post completion comment to issue

```bash
gh issue comment {issue-id} --body "Work completed. PR created: {pr-url}"
```

---

# Command: issue-create

**Usage:** `/issue-create [operation]`

Create GitHub issues from conversation context.

## Operations

- **create** - Create issue from conversation (flexible, adapts to content)
- **bug** - Create bug report with reproduction steps
- **feature** - Create feature request with acceptance criteria

## Workflow

### Step 1: Analyze Conversation

Identify:
- What the user wants to accomplish
- The problem or need discussed
- Decisions or insights that emerged
- Relevant technical context

### Step 2: Determine Issue Type

- Feature request or enhancement
- Bug report or defect
- Technical task or chore
- Documentation need

### Step 3: Clarify with User

Ask 2-4 questions to confirm understanding and fill gaps.

### Step 4: Create Issue

```bash
gh issue create \
  --title "[type]: [description]" \
  --body "[content]" \
  --label "[labels]" \
  --assignee @me
```

**Title format:** Conventional commit style
- `feat:` for features
- `bug:` for defects
- `docs:` for documentation
- `refactor:` for improvements

---

# Command: issue-compact

**Usage:** `/issue-compact`

Consolidate issue discussion into clean body for handoff.

## Purpose

Enable handoff: someone unfamiliar with the history can pick up the issue and continue.

## Workflow

### Step 1: Fetch Issue Content

```bash
gh issue view {issue-id} --json number,title,body,comments
```

### Step 2: Analyze Context

Review conversation for:
- Requirement clarifications
- Design decisions
- Technical discoveries
- Plan adjustments

### Step 3: Synthesize Content

Create new issue body that preserves:
- Original requirements and context
- Key decisions and rationale
- Technical constraints
- Current status and next steps
- Blockers or open questions

Add compact metadata:
```
---
> Compacted on YYYY-MM-DD from X comments
```

### Step 4: Update Issue

```bash
gh issue edit {issue-id} --body-file /tmp/issue-{issue-id}-compact.md
```

### Step 5: Delete Comments

```bash
# Get repo info
gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'

# Get and delete each comment
gh api repos/{owner}/{repo}/issues/{issue-id}/comments --jq '.[].id'
gh api -X DELETE repos/{owner}/{repo}/issues/comments/{comment-id}
```

---

## Label Management

- **pending** - Waiting for user input (plan review, questions, blocked)
- Remove when resuming work
- Add when waiting for feedback

Create label if it doesn't exist:

```bash
gh label create pending --description "Waiting for human input" --color FFA500
```

## Best Practices

1. **Follow conventional commits** - feat / fix / docs / refactor / test / chore
2. **Small iterations** - Implement focused changes with tests
3. **Verify each change** - Run tests after each modification
4. **Don't deviate from plan** - Get approval for changes
5. **Reproduce bugs first** - Write failing test before fixing
