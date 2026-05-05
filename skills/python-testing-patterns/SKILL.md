---
name: python-testing-patterns
description: Implement comprehensive testing strategies with pytest, fixtures, mocking, and test-driven development. Use when writing Python tests, setting up test suites, or implementing testing best practices.
license: MIT
metadata:
  language: python
  scope: testing
  packages: pytest, responses, freezegun, hypothesis, unittest, pytest-cov, pytest-asyncio
---

# Python Testing Patterns

Navigation index for robust pytest-based testing. Each topic is in its own reference.

## When to Use

- Writing unit / integration / e2e tests in Python
- Setting up `pytest` infrastructure
- Adopting TDD
- Mocking external services, time, files
- Adding coverage and CI gating

## When NOT to Use

- Non-Python projects
- Legacy `unittest`-only codebases where the team prefers to stay (respect that)

## Quick Start

```python
# test_calculator.py
import pytest

class Calculator:
    def add(self, a, b): return a + b
    def divide(self, a, b):
        if b == 0:
            raise ValueError("Cannot divide by zero")
        return a / b


def test_add():
    assert Calculator().add(2, 3) == 5


def test_division_by_zero():
    with pytest.raises(ValueError, match="Cannot divide by zero"):
        Calculator().divide(5, 0)
```

Run: `pytest` (or `uv run pytest`).

## Decision Tree

```
What do you need?
│
├─ Setup/teardown shared between tests?
│   └─ references/fixtures.md
│
├─ Replace external dependency / env var?
│   └─ references/mocking.md
│
├─ Same test, many inputs?
│   └─ references/parametrize.md
│
├─ Test async code?
│   └─ references/async-testing.md
│
├─ Database / files / HTTP?
│   └─ references/integration.md
│
├─ Time-dependent behaviour?
│   └─ references/freeze-time.md
│
├─ Coverage and CI?
│   └─ references/coverage.md
│
└─ Naming, structure, exception tests, property-based?
    └─ references/design-principles.md
```

## Core Concepts

| Concept | Summary |
|--------|---------|
| **Test types** | unit (isolated), integration (interactions), e2e (full feature), perf (speed/resources) |
| **AAA pattern** | Arrange → Act → Assert |
| **Isolation** | No shared mutable state between tests |
| **Coverage** | Measure exercised paths; aim for *meaningful*, not maximal |

## Tooling Cheatsheet

```bash
# Install
uv add --group dev pytest pytest-cov pytest-asyncio freezegun responses hypothesis

# Run all
pytest

# Run one file / one test
pytest tests/test_x.py
pytest tests/test_x.py::test_specific

# Markers
pytest -m "not slow"

# Coverage
pytest --cov=myapp --cov-report=term-missing
```

## Best Practices Checklist

- [ ] Tests are independent and order-insensitive
- [ ] Each test name describes the behavior under test
- [ ] One behavior per test (use parametrize for variants)
- [ ] External I/O is mocked or uses an in-memory equivalent
- [ ] Error paths are tested, not just happy paths
- [ ] Custom markers are registered in `pyproject.toml`
- [ ] CI runs the full suite with coverage on every push

## References

- [fixtures.md](./references/fixtures.md) — fixtures, scopes, conftest
- [mocking.md](./references/mocking.md) — `unittest.mock`, `monkeypatch`, retry tests
- [parametrize.md](./references/parametrize.md) — parametrized tests, custom IDs
- [async-testing.md](./references/async-testing.md) — `pytest-asyncio` patterns
- [integration.md](./references/integration.md) — DB, files, HTTP integration
- [freeze-time.md](./references/freeze-time.md) — `freezegun` for time control
- [coverage.md](./references/coverage.md) — `pytest-cov`, markers, CI
- [design-principles.md](./references/design-principles.md) — naming, structure, property-based, AAA

## Resources

- pytest: https://docs.pytest.org/
- unittest.mock: https://docs.python.org/3/library/unittest.mock.html
- hypothesis: https://hypothesis.readthedocs.io/
- responses: https://github.com/getsentry/responses
