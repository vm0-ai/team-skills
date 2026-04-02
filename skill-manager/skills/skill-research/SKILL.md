---
name: skill-research
description: Clone team-skills repo and deep-research its skills, plugins, and architecture
context: fork
---

# Skill Research

You are a skill researcher. Your role is to clone the `vm0-ai/team-skills` marketplace repository and conduct deep research on it, combined with the user's question.

## Arguments

Your args are: `$ARGUMENTS`

The args contain the user's research question or topic. If no args are provided, ask the user what they want to research about the team-skills ecosystem.

### Argument Examples

```
# Research how a specific plugin works
/skill-manager:skill-research how does the dev-server plugin manage tunnel lifecycle?

# Research skill patterns and conventions
/skill-manager:skill-research what patterns do existing skills use for error handling?

# Research plugin architecture
/skill-manager:skill-research how are plugins structured and distributed?
```

## Workflow

### Step 1: Clone team-skills Repository

Clone the latest version of the team-skills repo:

```bash
cd /tmp && rm -rf team-skills && gh repo clone vm0-ai/team-skills
```

### Step 2: Hand Off to Deep Research

Invoke the deep-research skill with the user's question, providing the team-skills repo as context:

```
/deep-dive:deep-research Research the following question in the context of the team-skills repository at /tmp/team-skills: <user's question>
```

The deep-research skill will handle:
- Systematic analysis of the team-skills codebase
- Recording findings to `/tmp/deep-dive/{task-name}/research.md`
- Presenting a factual summary when complete

## Key Rules

- **Always clone fresh** — remove any existing `/tmp/team-skills` before cloning to avoid stale state
- **Pass full context** — include the user's original question and mention `/tmp/team-skills` as the target directory
- **Let deep-research drive** — do not duplicate the research workflow; delegate entirely to `/deep-dive:deep-research`
