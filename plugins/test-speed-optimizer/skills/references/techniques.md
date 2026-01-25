# Test Speed Optimization Guide

Patterns and techniques for making test suites faster, extracted from real optimizations that reduced test time from >3 minutes to ~15 seconds.

## Quick Reference

| Technique | Impact | Effort | When to Use |
|-----------|--------|--------|-------------|
| Disable unused env features | 90%+ | Low | Tests timing out on unavailable services |
| Transaction rollback | 30-50% | Medium | Database-heavy test suites |
| Lazy imports | 50-75% collection | Medium | Heavy dependencies in package `__init__` |
| Remove slow plugins | 10-25% | Low | Using pytest-sugar or similar |
| Reduce artificial delays | 10-30% | Low | Tests with `sleep()` calls |
| Test impact analysis | 80-95% incremental | Low | Large test suites, frequent runs |
| Coordination primitives | 5-10x for timing tests | Medium | Concurrency tests using delays |
| Block network calls | Prevents regressions | Low | Tests accidentally hitting network |
| VCR cassette recording | API cost → $0 | Medium | External API integration tests |
| Parallel execution | Scales with CPUs | Low | CPU-bound test suites |

---

## Tier 1: Major Impact (>30% improvement)

### 1. Disable Unused Environment Features

**Impact:** 90%+ reduction
**Effort:** Low

#### Problem

Tests time out or run slowly because they try to connect to services configured in `.env` for production but unavailable in test environments:

- Redis/Memcached connections timing out
- External proxy services
- Authentication servers
- Message queues (RabbitMQ, Kafka)
- Cloud services (S3, external APIs)

#### Solution

Auto-disable production features in tests that aren't available or needed:

```python
# tests/conftest.py
@pytest.fixture(autouse=True)
def disable_external_services(monkeypatch: pytest.MonkeyPatch) -> None:
    """Disable external services in tests - they're not available."""
    monkeypatch.setenv("USE_REDIS", "0")
    monkeypatch.setenv("USE_EXTERNAL_AUTH", "0")
    monkeypatch.setenv("CACHE_BACKEND", "memory")
```

For tests that actually need the feature, use a marker:

```python
@pytest.fixture(autouse=True)
def disable_external_services(request, monkeypatch: pytest.MonkeyPatch) -> None:
    """Disable external services except for integration tests."""
    if "integration" not in request.keywords:
        monkeypatch.setenv("USE_REDIS", "0")
        monkeypatch.setenv("CACHE_BACKEND", "memory")
```

#### When to Use

- Tests timing out waiting for external services (proxies, databases, caches)
- Environment variables enable features not available in CI
- Production configs leak into test environment

#### Checklist

- [ ] Identify environment variables that enable slow/unavailable features
- [ ] Add autouse fixture to override them for tests
- [ ] Allow specific tests to opt-in via markers

---

### 2. Transaction Rollback for Database Tests

**Impact:** 30-50% faster
**Effort:** Medium

#### Problem

Each test created fresh database tables, which is expensive:
- SQLite: ~50ms per test for table creation
- PostgreSQL: ~200ms+ per test
- With 100 database tests, that's 5-20 seconds of pure setup overhead

#### Solution

Create tables once per session, run each test in a transaction, rollback after:

```python
# tests/conftest.py
from sqlalchemy import create_engine
from sqlmodel import SQLModel

# Session-scoped engine - created once, reused across all tests
_test_engine = None

@pytest.fixture(scope="session")
def _session_engine():
    """Create test database engine once per session."""
    global _test_engine

    _test_engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    SQLModel.metadata.create_all(_test_engine)

    yield _test_engine
    _test_engine.dispose()


@pytest.fixture
def db_session(_session_engine):
    """Per-test session with transaction rollback for isolation."""
    connection = _session_engine.connect()
    transaction = connection.begin()

    # Create a session bound to this connection
    session = Session(bind=connection)

    yield session

    # Rollback to undo all changes from this test
    session.close()
    transaction.rollback()
    connection.close()
```

#### When to Use

- Test suite has many database tests (>20)
- Tests create/modify database records
- Using SQLAlchemy, SQLModel, Django ORM, or similar

#### Checklist

- [ ] Create session-scoped fixture for engine/table creation
- [ ] Create function-scoped fixture that wraps tests in transactions
- [ ] Ensure tests don't commit transactions (or use savepoints)
- [ ] Handle any one-time initialization (FTS, extensions) at session scope

#### Caveats

- Tests can't test commit/rollback behavior directly
- Some ORMs have issues with nested transactions (use savepoints)
- Parallel test execution needs separate connections per worker

---

### 3. Lazy Imports in Package `__init__.py`

**Impact:** 50-75% faster collection, faster imports
**Effort:** Medium

#### Problem

Package `__init__.py` eagerly imported heavy dependencies:

```python
# src/mypackage/__init__.py (SLOW)
from mypackage.services import SummarizerService  # Imports google.genai (~500ms)
from mypackage.db import engine  # Imports sqlalchemy (~200ms)
```

Even when tests only needed a small submodule, the entire dependency tree loaded.

#### Solution

Use `__getattr__` for lazy imports:

```python
# src/mypackage/__init__.py (FAST)
from typing import TYPE_CHECKING

__all__ = [
    "SummarizerService",
    "create_app",
]

if TYPE_CHECKING:
    # Static type checkers see the real types
    from mypackage.services import SummarizerService
    from mypackage.web_app import create_app


def __getattr__(name: str) -> object:
    """Lazy import heavy modules only when accessed."""
    if name == "SummarizerService":
        from mypackage.services import SummarizerService
        return SummarizerService
    if name == "create_app":
        from mypackage.web_app import create_app
        return create_app
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
```

#### Verifying the Fix

Add a test to prevent regression:

```python
# tests/test_import_performance.py
import subprocess
import sys

def test_package_import_does_not_load_heavy_deps():
    """Importing the package should not load heavy dependencies."""
    result = subprocess.run(
        [sys.executable, "-c", """
import sys
import mypackage
if 'google.genai' in sys.modules:
    print('FAIL: google.genai was imported')
    sys.exit(1)
print('OK')
"""],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Heavy dep imported: {result.stderr}"
```

#### When to Use

- Package `__init__.py` imports from modules with heavy dependencies
- Test collection is slow (>3 seconds)
- `python -c "import mypackage"` takes >500ms

#### Checklist

- [ ] Profile imports: `python -X importtime -c "import mypackage" 2>&1 | head -50`
- [ ] Identify heavy dependencies (google.*, sqlalchemy, pandas, torch)
- [ ] Convert eager imports to `__getattr__` lazy imports
- [ ] Keep `TYPE_CHECKING` block for static analysis
- [ ] Add regression test to verify lazy loading

---

## Tier 2: Moderate Impact (10-30%)

### 4. Remove Slow Pytest Plugins

**Impact:** 10-25% faster
**Effort:** Low

#### Problem

pytest-sugar adds pretty progress bars but has significant overhead:
- Intercepts every test result
- Updates terminal output constantly
- Adds ~8 seconds to a 30-second test suite

#### Solution

Remove or conditionally disable slow plugins:

```bash
# Remove entirely
uv remove pytest-sugar

# Or disable via pyproject.toml for CI
[tool.pytest.ini_options]
addopts = "-p no:sugar"  # Disable pytest-sugar
```

#### Common Slow Plugins

| Plugin | Overhead | Alternative |
|--------|----------|-------------|
| pytest-sugar | 5-10s | Use `-q` for quiet output |
| pytest-cov (always on) | 10-30% | Run coverage separately |
| pytest-randomly | 1-2s | Only for CI |
| pytest-timeout (per-test) | 0.5s/test | Use `--timeout` flag instead |

#### When to Use

- Test suite feels slower than it should
- Using multiple pytest plugins
- CI/local have different speed requirements

#### Checklist

- [ ] List plugins: `pytest --co -q` and check load time
- [ ] Benchmark with/without: `time pytest --collect-only`
- [ ] Remove or disable non-essential plugins
- [ ] Consider separate CI vs local configs

---

### 5. Reduce Artificial Delays in Tests

**Impact:** 10-30% faster
**Effort:** Low

#### Problem

Tests used long delays "to be safe":

```python
# SLOW: Excessive delays
async def test_concurrent_requests():
    delay_per_operation = 0.5  # 500ms per fake operation
    # 3 requests × 0.5s = 1.5s minimum test time
```

#### Solution

Use minimal delays that still prove the behavior:

```python
# FAST: Minimal delays that still prove concurrency
async def test_concurrent_requests():
    delay_per_operation = 0.1  # 100ms is enough to prove concurrency
    # 3 requests × 0.1s = 0.3s minimum test time
```

Also fix tests that accidentally trigger slow code paths:

```python
# SLOW: "invalid_url" is 11 chars, looks like a video ID, triggers network lookup
response = client.post("/", data={"url": "invalid_url"})

# FAST: "invalid" is clearly not a video ID, rejected immediately
response = client.post("/", data={"url": "invalid"})
```

#### When to Use

- Tests have `time.sleep()` or `asyncio.sleep()` calls
- Test inputs accidentally look valid and trigger slow validation
- Tests are marked `@slow` but don't need to be

#### Checklist

- [ ] Search for `sleep(` in test files
- [ ] Reduce delays to minimum needed (usually 0.05-0.1s)
- [ ] Adjust assertions proportionally
- [ ] Check that invalid test inputs are obviously invalid

---

### 6. Test Impact Analysis (testmon)

**Impact:** 80-95% reduction on incremental runs
**Effort:** Low

#### Problem

Running all tests after every change is wasteful:
- Changed one file? All 800 tests run.
- Fixed a typo? Wait 40 seconds.

#### Solution

Use pytest-testmon to run only affected tests:

```bash
# Install
uv add --dev pytest-testmon

# Configure in pyproject.toml
[tool.pytest.ini_options]
addopts = "--testmon"
```

```bash
# justfile
# Default: run only affected tests
test:
    uv run pytest --testmon

# Full run for CI
test-full:
    uv run pytest --testmon-noselect

# Reset database if corrupted
test-reset:
    rm -f .testmondata
    uv run pytest --testmon
```

#### How It Works

1. First run: builds dependency database (~full test time)
2. Subsequent runs: analyzes changed files, runs only affected tests
3. Database stored in `.testmondata` (gitignore it)

#### When to Use

- Large test suite (>100 tests)
- Frequent test runs during development
- Tests have clear file dependencies

#### Checklist

- [ ] Install pytest-testmon
- [ ] Add `.testmondata` to `.gitignore`
- [ ] Create separate commands for affected vs full runs
- [ ] Copy `.testmondata` to new worktrees for instant incremental runs

#### Caveats

- First run is full speed (builds database)
- Database can get corrupted (just delete it)
- Some dynamic imports may not be tracked

---

## Tier 3: Targeted Optimizations

### 7. Coordination Primitives Instead of Timing

**Impact:** 5-10x faster for concurrency tests
**Effort:** Medium

#### Problem

Concurrency tests used timing to prove parallel execution:

```python
# SLOW & FLAKY: Timing-based concurrency test
async def test_concurrent_execution():
    start = time.perf_counter()
    await asyncio.gather(task1(), task2(), task3())
    elapsed = time.perf_counter() - start

    # Flaky: CI machines have variable performance
    assert elapsed < 0.5, "Tasks should run in parallel"
```

#### Solution

Use `asyncio.Barrier` to prove concurrency without delays:

```python
# tests/fake_services.py
class ConcurrencyTracker:
    """Tracks concurrent invocations without real-time delays."""

    def __init__(self, expected_concurrent: int = 1) -> None:
        self._barrier = asyncio.Barrier(expected_concurrent)
        self._max_concurrent = 0
        self._current = 0
        self._lock = asyncio.Lock()

    async def checkpoint(self) -> None:
        """Wait until expected concurrent calls arrive."""
        async with self._lock:
            self._current += 1
            self._max_concurrent = max(self._max_concurrent, self._current)

        await self._barrier.wait()  # All must arrive before any proceed

        async with self._lock:
            self._current -= 1

    @property
    def max_concurrent(self) -> int:
        return self._max_concurrent
```

```python
# FAST & DETERMINISTIC: Barrier-based test
async def test_concurrent_execution():
    tracker = ConcurrencyTracker(expected_concurrent=3)

    async def task():
        await tracker.checkpoint()
        return "done"

    results = await asyncio.gather(task(), task(), task())

    assert tracker.max_concurrent == 3  # Proves all 3 ran concurrently
```

#### When to Use

- Tests verify concurrent execution
- Tests are flaky due to timing assumptions
- Tests use arbitrary sleep() to simulate work

#### Checklist

- [ ] Identify timing-based concurrency tests
- [ ] Create ConcurrencyTracker or similar utility
- [ ] Inject tracker into fake services
- [ ] Replace timing assertions with counter assertions

---

### 8. Block Unintended Network Calls

**Impact:** Prevents regressions, catches slow tests early
**Effort:** Low

#### Problem

Tests accidentally made network calls:
- Forgot to mock an HTTP client
- Test input looked like a real URL
- Third-party library made unexpected requests

#### Solution

Use pytest-socket to block all network by default:

```bash
uv add --dev pytest-socket
```

```toml
# pyproject.toml
[tool.pytest.ini_options]
addopts = "--disable-socket --allow-unix-socket"
```

```python
# tests/conftest.py
def pytest_runtest_setup(item):
    """Re-enable sockets for tests that need real network."""
    if "real_api" in item.keywords:
        import pytest_socket
        pytest_socket.enable_socket()
```

#### When to Use

- Tests should be hermetic (no network)
- Some tests accidentally hit real APIs
- Want to catch network calls during development

#### Checklist

- [ ] Install pytest-socket
- [ ] Add `--disable-socket --allow-unix-socket` to addopts
- [ ] Add hook to re-enable for integration test markers
- [ ] Fix tests that fail (they were making network calls!)

---

### 9. VCR Cassette Recording for API Tests

**Impact:** API costs → $0 after recording, faster replays
**Effort:** Medium

#### Problem

Integration tests hitting real APIs are:
- Expensive (pay per call)
- Slow (network latency)
- Flaky (rate limits, outages)

#### Solution

Use VCR.py to record and replay HTTP interactions:

```bash
uv add --dev vcrpy
```

```python
# tests/conftest.py
import vcr

vcr_config = vcr.VCR(
    cassette_library_dir="tests/cassettes",
    record_mode="once",  # Record first time, replay after
    match_on=["method", "scheme", "host", "port", "path", "query"],
    filter_headers=["authorization", "x-api-key"],  # Remove secrets
    decode_compressed_response=True,
)

@pytest.fixture
def vcr_cassette(request):
    """Auto-named cassette based on test name."""
    cassette_name = f"{request.node.nodeid.replace('/', '_')}.yaml"
    with vcr_config.use_cassette(cassette_name):
        yield
```

```python
# tests/test_api.py
@pytest.mark.real_api
async def test_real_api_call(vcr_cassette):
    result = await external_api.fetch_data()
    assert result.status == "success"
```

```bash
# justfile
# Run with cassettes (replay mode, no API key needed)
test-vcr:
    uv run pytest -m real_api

# Re-record cassettes (requires API key)
test-vcr-refresh:
    rm -rf tests/cassettes/*.yaml
    uv run pytest -m real_api
```

#### When to Use

- Tests call external APIs (AI, payment, etc.)
- API calls are expensive or rate-limited
- Want deterministic CI without API credentials

#### Limitations

- VCR only intercepts HTTP libraries (requests, httpx, urllib)
- Tools using raw sockets (yt-dlp) bypass VCR
- Cassettes can become stale when APIs change

#### Checklist

- [ ] Install vcrpy
- [ ] Configure cassette directory and filtering
- [ ] Create fixture for automatic cassette naming
- [ ] Add cassettes to git (after reviewing for secrets)
- [ ] Create commands for replay vs re-record

---

### 10. Parallel Test Execution

**Impact:** Scales with CPU cores (4 cores ≈ 3x faster)
**Effort:** Low

#### Problem

Tests run sequentially by default, leaving CPU cores idle.

#### Solution

Use pytest-xdist for parallel execution:

```bash
uv add --dev pytest-xdist
```

```bash
# Run with auto-detected parallelism
pytest -n auto

# Run with specific worker count
pytest -n 4
```

```toml
# pyproject.toml (optional default)
[tool.pytest.ini_options]
addopts = "-n auto"
```

#### When to Use

- Test suite is CPU-bound (not I/O-bound)
- Tests are isolated (don't share state)
- Have multiple CPU cores available

#### Caveats

- Tests must be truly isolated
- Database fixtures need per-worker connections
- Some pytest plugins don't work with xdist
- I/O-bound tests won't benefit much

#### Checklist

- [ ] Install pytest-xdist
- [ ] Run `pytest -n auto` and check for failures
- [ ] Fix tests that assume sequential execution
- [ ] Ensure database fixtures are worker-safe

---

## Measurement & Profiling

### How to Measure Test Speed

```bash
# Total time
time pytest

# Per-test timing
pytest --durations=10  # Show 10 slowest tests

# Collection time
time pytest --collect-only

# Import time
python -X importtime -c "import mypackage" 2>&1 | head -30
```

### Profiling Test Collection

```bash
# See what's slow during collection
pytest --collect-only -q 2>&1 | tail -5

# Profile imports
python -c "
import time
start = time.time()
import mypackage
print(f'Import time: {time.time() - start:.2f}s')
"
```

---

## Summary: Recommended Order of Attack

1. **Check for environment timeouts** - Quick win, often 90%+ improvement
2. **Profile collection time** - If >3s, check for heavy imports
3. **Add transaction rollback** - If many database tests
4. **Remove slow plugins** - pytest-sugar, always-on coverage
5. **Reduce test delays** - Search for `sleep(`
6. **Add testmon** - For large suites with frequent runs
7. **Block network** - Prevent future regressions
8. **Add VCR** - If testing external APIs
9. **Try parallel execution** - If tests are isolated
10. **Optimize specific slow tests** - Use `--durations=10` to find them
