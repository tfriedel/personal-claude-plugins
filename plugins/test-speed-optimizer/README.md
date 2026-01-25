# Test Speed Optimizer

A Claude Code skill for optimizing pytest test suite performance.

## What It Does

This skill helps you analyze and speed up slow pytest test suites using proven techniques that have reduced test times from >3 minutes to ~15 seconds.

## When to Use

- Tests are running slowly
- User asks to speed up tests
- Analyzing test performance issues

## Features

- Quick diagnosis commands for measuring test speed
- Priority table showing impact vs effort for each technique
- 10 optimization techniques with code examples
- Implementation checklists for each technique

## Techniques Covered

| Technique | Impact | Effort |
|-----------|--------|--------|
| Disable unused env features | 90%+ | Low |
| Transaction rollback (DB tests) | 30-50% | Medium |
| Lazy imports in `__init__.py` | 50-75% collection | Medium |
| Remove slow plugins | 10-25% | Low |
| Reduce artificial delays | 10-30% | Low |
| testmon (incremental runs) | 80-95% | Low |
| Block network calls | Prevents regressions | Low |
| VCR cassettes (API tests) | Cost → $0 | Medium |
| Parallel execution | Scales with CPUs | Low |

## Usage

The skill triggers when you ask about slow tests or test optimization. Example prompts:

- "My tests are running slowly"
- "How can I speed up my pytest tests?"
- "Analyze test performance"
