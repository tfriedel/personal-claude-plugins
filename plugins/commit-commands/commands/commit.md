---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*)
description: Create a git commit
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your task

Based on the above changes, create a single git commit using Conventional Commits format.
- Use lowercase after prefix: `feat: add feature` not `feat: Add feature`

You must use the following prefixes:
| Prefix | Group |
|----------|---------------|
| feat | Features |
| fix | Bug Fixes |
| docs | Documentation |
| perf | Performance |
| refactor | Refactoring |
| style | Style |
| test | Testing |
| chore | Miscellaneous |
| ci | CI/CD |

You have the capability to call multiple tools in a single response. Stage and create the commit using a single message. Do not use any other tools or do anything else. Do not send any other text or messages besides these tool calls.
