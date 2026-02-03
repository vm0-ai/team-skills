# team-skills

A collection of AI-assisted development workflow skills for [Claude Code](https://claude.ai/claude-code).

Skills follow the [Agent Skills specification](https://agentskills.io/specification).

## Overview

This repository provides structured workflows for software development with AI assistance:

- **Deep Dive Workflow** - Systematic approach to complex tasks: research → innovate → plan
- **GitHub Issue Workflow** - Manage GitHub issues with AI-assisted planning and implementation

## Installation

### Using Claude Code Marketplace

```bash
# Add marketplace
/plugin marketplace add vm0-ai/team-skills

# Install the plugin
/plugin install team-skills@team-skills
```

### Direct Download

```bash
# Clone the repository
git clone https://github.com/vm0-ai/team-skills.git

# Copy to personal skills directory
cp -a team-skills/deep-dive ~/.claude/skills/
cp -a team-skills/github-workflow ~/.claude/skills/

# Or copy to project directory
cp -a team-skills/deep-dive ./.claude/skills/
cp -a team-skills/github-workflow ./.claude/skills/
```

After installation, restart Claude Code, then ask "What skills are available?" to see installed skills.

## Available Skills

### Deep Dive Workflow

Structured approach for tackling complex development tasks:

| Skill | Description |
|-------|-------------|
| `deep-research` | Information gathering phase - analyze codebase without suggesting solutions |
| `deep-innovate` | Brainstorming phase - explore multiple approaches and trade-offs |
| `deep-plan` | Planning phase - create concrete implementation steps |

### GitHub Issue Workflow

AI-assisted GitHub issue management:

| Skill | Description |
|-------|-------------|
| `issue-plan` | Start working on an issue with full deep-dive workflow |
| `issue-action` | Continue implementation based on approved plan |
| `issue-create` | Create issues from conversation context |
| `issue-compact` | Consolidate issue discussion into clean body |

## Prerequisites

- [Claude Code](https://claude.ai/claude-code) installed
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated

## Contributing

1. Follow the [Agent Skills specification](https://agentskills.io/specification)
2. Include a `SKILL.md` file with clear instructions
3. Test the skill thoroughly
4. Submit a pull request

## License

MIT
