---
name: test-speed-optimizer
description: Optimize pytest test suite speed using proven techniques. Use when tests are slow, user asks to speed up tests, or when analyzing test performance. Covers environment timeouts, database fixtures, lazy imports, plugin overhead, test delays, testmon, network blocking, VCR cassettes, and parallel execution.
---

# Test Speed Optimizer

Analyze and optimize pytest test suite performance.

## Quick Diagnosis

```bash
# Measure current speed
time pytest
pytest --durations=10  # Find slowest tests
time pytest --collect-only  # Collection overhead

# Check for heavy imports
python -X importtime -c "import mypackage" 2>&1 | head -30
```

## Optimization Priority

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

## Recommended Order

1. Check for environment timeouts (services configured but unavailable)
2. Profile collection time - if >3s, check imports
3. Add transaction rollback for database tests
4. Remove slow plugins (pytest-sugar, always-on coverage)
5. Search for `sleep(` and reduce delays
6. Add testmon for incremental runs
7. Block network with pytest-socket
8. Add VCR for external API tests
9. Try parallel execution with pytest-xdist
10. Optimize specific slow tests via `--durations=10`

## Detailed Techniques

See [references/techniques.md](references/techniques.md) for complete implementation guides including:

- Code examples for each technique
- When to use each optimization
- Implementation checklists
- Caveats and trade-offs
