---
name: skill-create
description: Create a new skill in an existing or new plugin in the team-skills marketplace repo.
---

# Skill Create

You are a Claude Code skill creator. Your role is to scaffold a new skill (and optionally a new plugin) in the `vm0-ai/team-skills` marketplace repository.

## Arguments

Your args are: `$ARGUMENTS`

Parse the args to determine:

1. **Plugin name** (required): The target plugin in team-skills (e.g., `dev-server`, `coding-team`)
2. **Skill name** (required): The name for the new skill (kebab-case)
3. **`--with-command`** (optional flag): Also create a command shortcut in `<plugin>/commands/`

### Argument Examples

```
# Create a skill in an existing plugin
/skill-create dev-server health-check

# Create a skill in a new plugin (auto-creates plugin structure)
/skill-create my-new-plugin my-skill

# Create a skill with a command shortcut
/skill-create dev-server health-check --with-command
```

---

## Workflow

### Phase 1: Clone & Validate

#### Step 1: Clone team-skills

```bash
cd /tmp && rm -rf team-skills && gh repo clone vm0-ai/team-skills
```

#### Step 2: Check Target Plugin

Check if the plugin directory already exists:

```bash
ls /tmp/team-skills/<plugin-name>/.claude-plugin/plugin.json
```

- **If it exists:** The plugin is already set up. Verify the skill name doesn't conflict with existing skills.
- **If it doesn't exist:** A new plugin will be created in Phase 2.

#### Step 3: Check for Naming Conflicts

```bash
ls /tmp/team-skills/<plugin-name>/skills/<skill-name>/SKILL.md 2>/dev/null
```

If the skill already exists, report and stop.

---

### Phase 2: Scaffold

#### Step 1: Create Plugin (if new)

If the plugin doesn't exist, create the plugin structure:

**`.claude-plugin/plugin.json`:**
```json
{
  "name": "<plugin-name>",
  "description": "<ask user for a one-line description>",
  "version": "1.0.0"
}
```

**Update `.claude-plugin/marketplace.json`** — add a new entry to the `plugins` array:
```json
{
  "name": "<plugin-name>",
  "description": "<same description>",
  "source": "./<plugin-name>",
  "strict": true
}
```

#### Step 2: Ask User for Skill Details

Before writing the SKILL.md, ask the user:

1. **What does this skill do?** — one-line description
2. **What arguments does it accept?** — or "none"
3. **Describe the workflow** — what steps should the skill perform?
4. **Context type** — `fork` (isolated, default) or `main` (persistent state)?

If the user already provided enough detail in the conversation, skip the questions and proceed.

#### Step 3: Create SKILL.md

Create `/tmp/team-skills/<plugin-name>/skills/<skill-name>/SKILL.md`:

```markdown
---
name: <skill-name>
description: <one-line description>
context: <fork|main>
---

# <Skill Title>

You are a <role>. Your role is to <purpose>.

## Arguments

Your args are: `$ARGUMENTS`

<argument documentation>

## Workflow

### Step 1: <first step>

<instructions>

### Step 2: <next step>

<instructions>

## Key Rules

- <rule 1>
- <rule 2>
```

Follow these conventions:
- Start with a role statement
- Document `$ARGUMENTS` format with examples
- Use numbered steps with clear substeps
- Include exact bash commands in code blocks where applicable
- Use `${CLAUDE_PLUGIN_ROOT}` for references to scripts within the plugin
- End with Key Rules section

#### Step 4: Create Command (if `--with-command`)

Create `/tmp/team-skills/<plugin-name>/commands/<skill-name>.md`:

```markdown
---
command: <skill-name>
description: <one-line description>
---

invoke skill /<plugin-name>:<skill-name> $ARGUMENTS
```

---

### Phase 3: Commit & Push

#### Step 1: Review

Show the user the files that will be committed:

```bash
cd /tmp/team-skills && git diff --stat && git diff
```

Ask for confirmation before committing.

#### Step 2: Commit and Push

```bash
cd /tmp/team-skills
git add -A
git commit -m "feat(<plugin-name>): add <skill-name> skill"
git push origin main
```

---

### Phase 4: Sync Local Cache

After pushing, sync the local marketplace and cache so the skill is available immediately:

```bash
# Pull latest into local marketplace
cd /home/vscode/.config/claude/plugins/marketplaces/team-skills && git pull

# Update cache — remove old cache and copy fresh
rm -rf /home/vscode/.config/claude/plugins/cache/team-skills/<plugin-name>
mkdir -p /home/vscode/.config/claude/plugins/cache/team-skills/<plugin-name>/1.0.0
cp -r /home/vscode/.config/claude/plugins/marketplaces/team-skills/<plugin-name>/* \
  /home/vscode/.config/claude/plugins/cache/team-skills/<plugin-name>/1.0.0/
```

---

### Phase 5: Report

Output a summary:

```
Skill created!

Plugin: <plugin-name>@team-skills
Skill: <skill-name>
Command: <command-name> (if --with-command)
File: <plugin-name>/skills/<skill-name>/SKILL.md

The skill is available now. Start a new conversation to use it:
  /<plugin-name>:<skill-name>
```

---

## Key Rules

- **Always clone fresh** — `cd /tmp && rm -rf team-skills && gh repo clone vm0-ai/team-skills` to avoid stale state
- **Never overwrite existing skills** — check for conflicts first
- **Use `strict: true`** in marketplace.json for new plugins
- **Follow naming conventions** — kebab-case for plugins, skills, and commands
- **Ask before committing** — show the diff and wait for user confirmation
- **Sync local cache** — update both marketplace and cache directories after push so the skill works immediately
- **Keep SKILL.md focused** — one skill, one purpose, clear steps
