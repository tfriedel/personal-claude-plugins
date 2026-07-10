---
name: file-search
description: >-
  Find files and folders anywhere on this Windows machine, instantly, by name,
  extension, path, size, or date, using Everything's es.exe command-line search.
  Use this whenever the user wants to locate files across the whole system — "where
  is X", "find all .flac files", "which folder has my Cargo.toml", "find files
  bigger than 1GB", "list photos modified this week", "did I download that
  installer" — especially when the target may live outside the current project
  directory and a recursive Grep/Glob would be far too slow. Prefer this over
  `Get-ChildItem -Recurse`, `dir /s`, or `find` for any whole-disk or whole-user
  file lookup. Also handles the case where the Everything index is not running by
  starting it first.
---

# File search with Everything (es.exe)

Everything (voidtools) keeps a live index of every file on the NTFS volumes. Its
CLI, `es.exe`, answers whole-disk queries in milliseconds — where a recursive
`Get-ChildItem`/Glob would take minutes. Reach for this for any "find files
anywhere" task, not just inside the current project.

Requires `es.exe` on PATH (`choco install es`, or the voidtools ES download) and
Everything installed. If `es.exe` is missing the wrapper prints an install hint.

## The one habit that matters: always cap results

The search itself is instant. What makes es feel slow is streaming a giant result
set back through the terminal — an unbounded `*.rs` can match 100,000+ files and
take 10+ seconds just to print. A bounded query returns in a few hundred ms.

So **always pass a result limit** with `-n <count>` (start around 50–100). If you
truly need the full set, export it to a file with `-export-txt out.txt` instead of
streaming it.

## How to run it

Use the bundled wrapper — it caps results by default (`-n 100` when you pass no
limit) and, crucially, **starts Everything automatically if it isn't running**
(es.exe exits 8 / "IPC unavailable" when the index is down). Everything else you
pass is forwarded to `es.exe` verbatim.

The wrapper lives in this skill's own directory. When this skill loads you are
shown its absolute base directory; the script is at `scripts/es-search.ps1` under
it. As a plugin, that resolves to:

```powershell
& "${CLAUDE_PLUGIN_ROOT}\skills\file-search\scripts\es-search.ps1" <es.exe args...>
```

(`${CLAUDE_PLUGIN_ROOT}` is set by Claude Code to this plugin's install path. If
it isn't expanded in your shell, use the absolute base directory the skill loader
printed instead.) In the examples below `es-search.ps1` is shorthand for that
full path.

Examples:

```powershell
# name substring, whole machine
es-search.ps1 -n 20 djtool

# by extension, limited
es-search.ps1 -n 50 ext:flac

# restrict to a folder subtree
es-search.ps1 -path "S:\projects\djtool" Cargo.toml

# folders only, with size + modified columns as CSV
es-search.ps1 -n 30 /ad -csv -size -date-modified djtool

# export the full result set instead of streaming it
es-search.ps1 -export-txt "$env:TEMP\all_flac.txt" ext:flac
```

You can also call `es.exe` directly once you know Everything is running; the
wrapper is only needed for the auto-start safety net and the default cap. When in
doubt, use the wrapper.

## Query syntax cheatsheet (Everything, not regex by default)

| Goal | Query |
|------|-------|
| Name contains word | `djtool` |
| Wildcard | `*.flac`, `warp_*.rs` |
| By extension | `ext:mp3` (or `ext:mp3;flac;wav` for several) |
| Multiple terms (AND) | `warp ext:rs` |
| OR | `ext:mp3 | ext:flac` |
| Exclude | `ext:rs !target` |
| Files only / folders only | `/a-d` / `/ad` |
| Size filter | `size:>1gb`, `size:100kb..1mb` |
| Date filter | `dm:today`, `dm:thisweek`, `dc:2024` (dm=modified, dc=created) |
| Match against full path | add `-p` (or use `-path <dir>` to scope a subtree) |
| Regex | add `-r` and write a regex instead |
| Case sensitive / whole word | `-i` / `-w` |

Useful output flags: `-n <count>` (limit), `-s` (sort by path),
`-sort size-descending` (sort by any column), `-csv` / `-txt` (format),
`-size -date-modified` (add columns), `-export-txt <file>` (dump to file).
Run `es.exe -h` for the full list.

## Common recipes

- **Locate a specific file:** `es-search.ps1 -n 10 <name-fragment>`
- **All files of a type in a project:** `es-search.ps1 -path "<dir>" ext:wav`
- **Biggest files on disk:** `es-search.ps1 -n 20 -sort size-descending size:>500mb -size`
- **Recently changed files:** `es-search.ps1 -n 30 dm:today -date-modified -sort date-modified-descending`
- **Count matches** (don't print them all): pipe through `Measure-Object -Line`, e.g.
  `(es-search.ps1 -n 1000000 ext:flac | Measure-Object -Line).Lines`
  (raise `-n` past the expected count so the cap doesn't truncate the count).

## When Everything isn't running

The wrapper handles this for you. On exit code 8 (`Everything IPC window not
found`) it starts the Everything Windows service if present, launches a
background (`-startup`, tray-only) index process, then **polls until the index is
ready under a time budget** (default 120s, override with the
`ES_SEARCH_RECOVERY_BUDGET_SEC` env var).

Why a budget instead of just waiting: on a cold start Everything must rescan
every NTFS volume before it can answer *any* query, and es blocks that whole time
— on large drives this measured up to ~6 minutes, and es ignores its own
`-timeout` during an active build. So the wrapper probes with short hard-capped
es calls and returns the instant the index is ready; if the budget elapses first
it returns promptly with exit 8 and a message like *"Everything has been started
and is building its index … re-run the search shortly."* That is the expected,
correct outcome for a first-ever cold start on a big machine — just run the same
search again a minute later and it will be instant. If it *keeps* failing across
retries, Everything may need to be opened interactively once (first-run indexing
/ admin prompt); tell the user to launch it manually.

Note the normal case is cheap: when Everything is already running (its usual
state), the wrapper's first es call answers in milliseconds and none of the
recovery logic runs.

## When NOT to use this

- Searching *inside* file contents (not names/paths) → use Grep/ripgrep.
- Working only within the current repo and Glob/Grep is already fast enough.
- Non-NTFS or network locations Everything doesn't index → fall back to
  `Get-ChildItem`.
