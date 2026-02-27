# Claude Code Plugins

A [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins) with custom plugins for git workflows, code review, and test optimization.

## Plugins

| Name | Description |
|------|-------------|
| [commit-commands](./plugins/commit-commands/) | `/commit`, `/commit-push-pr`, `/clean_gone` — git workflow automation |
| [code-review](./plugins/code-review/) | `/code-review` — automated PR review with confidence-based scoring |
| [test-speed-optimizer](./plugins/test-speed-optimizer/) | Optimize pytest test suite speed using proven techniques |

## Installation

Add this marketplace to your Claude Code settings:

```bash
claude mcp add-plugin-marketplace https://github.com/tfriedel/personal-claude-plugins
```

Or add it manually in `.claude/settings.json`:

```json
{
  "pluginMarketplaces": [
    "https://github.com/tfriedel/personal-claude-plugins"
  ]
}
```

Then install individual plugins with `/install-plugin`.

## Plugin Structure

Each plugin follows the standard [Claude Code plugin structure](https://docs.claude.com/en/docs/claude-code/plugins):

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json      # Plugin metadata
├── commands/             # Slash commands (optional)
├── agents/               # Specialized agents (optional)
├── skills/               # Agent skills (optional)
├── hooks/                # Event handlers (optional)
└── README.md
```
