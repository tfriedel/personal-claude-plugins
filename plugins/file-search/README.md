# file-search

Instantly find files and folders **anywhere** on a Windows machine by name,
extension, path, size, or date — using [Everything](https://www.voidtools.com/)'s
`es.exe` command-line search, which queries a live NTFS index in milliseconds
instead of walking the filesystem.

Claude reaches for this skill automatically for whole-disk lookups ("where is
X?", "find all .flac files", "which folder has my Cargo.toml", "biggest files on
disk") — the kind of search where a recursive `Get-ChildItem`/Glob would take
minutes and might miss drives entirely.

## What the bundled wrapper adds

`skills/file-search/scripts/es-search.ps1` wraps `es.exe` with two safety nets:

1. **Auto-starts Everything when it isn't running.** `es.exe` exits with code 8
   (`Everything IPC window not found`) when the index process is down. The
   wrapper starts the Everything service and a tray instance, then polls until
   the index is ready under a time budget (default 120s, override with
   `ES_SEARCH_RECOVERY_BUDGET_SEC`). On a machine whose cold rebuild exceeds the
   budget it returns promptly with a "still building — re-run shortly" message
   rather than hanging.
2. **Caps results by default.** An unbounded query can match 100,000+ files; the
   search is instant but *printing* that many lines is what feels slow (~12s in
   practice). The wrapper injects `-n 100` when you pass no `-n`/`-max-results`/
   `-export-*`, cutting that to a few hundred ms — fully overridable.

## Requirements

- Windows with [Everything](https://www.voidtools.com/) installed.
- `es.exe` on `PATH` (`choco install es`, or the voidtools ES download).

## Usage

```powershell
& "${CLAUDE_PLUGIN_ROOT}\skills\file-search\scripts\es-search.ps1" -n 20 djtool
& "${CLAUDE_PLUGIN_ROOT}\skills\file-search\scripts\es-search.ps1" -n 10 ext:flac -sort size-descending -size
& "${CLAUDE_PLUGIN_ROOT}\skills\file-search\scripts\es-search.ps1" -path "S:\projects\djtool" Cargo.toml
```

See `skills/file-search/SKILL.md` for the full Everything query-syntax cheatsheet
and recipes.
