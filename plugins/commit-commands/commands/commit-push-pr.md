---
allowed-tools: Bash(git checkout --branch:*), Bash(git add:*), Bash(git status:*), Bash(git push:*), Bash(git commit:*), Bash(gh pr create:*)
description: Commit, push, and open a PR
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`

## Your task

Based on the above changes:

1. Create a new branch if on main
2. Create a single commit using Convential Commits format with an appropriate message
3. Push the branch to origin
4. Create a pull request using `gh pr create`
5. You have the capability to call multiple tools in a single response. You MUST do all of the above in a single message. Do not use any other tools or do anything else. Do not send any other text or messages besides these tool calls.

When creating commits and PR titles, follow Conventional Commits format:
- Use lowercase after prefix: `feat: add feature` not `feat: Add feature`
- PR titles are validated by CI (PRs are squash-merged, so title becomes commit message)

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
