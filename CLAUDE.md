# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Claude Code plugin marketplace (`thomas-claude-plugins`) containing custom plugins that extend Claude Code functionality through commands, agents, skills, and hooks.

## Repository Structure

```
.claude-plugin/marketplace.json  # Marketplace metadata
plugins/
  commit-commands/               # Git workflow automation plugin
    .claude-plugin/plugin.json   # Plugin metadata
    commands/                    # Slash command definitions (.md files)
    README.md
```

## Plugin Structure

Each plugin follows the standard Claude Code plugin structure:
- `.claude-plugin/plugin.json` - Plugin metadata (name, description, version, author)
- `commands/` - Slash commands as markdown files with YAML frontmatter
- `agents/` - Specialized agent definitions (optional)
- `skills/` - Agent skills (optional)
- `hooks/` - Event handlers (optional)
- `.mcp.json` - External tool configuration (optional)

## Command File Format

Commands are markdown files with YAML frontmatter:

```markdown
---
allowed-tools: Bash(git add:*), Bash(git status:*)
description: Command description
---

## Context
- Dynamic context using: !`command`

## Your task
Instructions for what the command does
```

## Current Plugins

- **commit-commands**: Git workflow commands (`/commit`, `/commit-push-pr`, `/clean_gone`)
  - Conventional Commits required for both commit messages AND PR titles
  - Prefixes: `feat:`, `fix:`, `docs:`, `perf:`, `refactor:`, `style:`, `test:`, `chore:`, `ci:`
  - Use lowercase after prefix: `feat: add feature` not `feat: Add feature`
  - PR titles are validated by CI (PRs are squash-merged, so title becomes commit message)
