# Coverage with `pytest-cov`

```bash
uv add --group dev pytest-cov
```

## Common invocations

```bash
# Basic coverage
pytest --cov=myapp tests/

# HTML report at htmlcov/
pytest --cov=myapp --cov-report=html tests/

# Show missing lines in terminal
pytest --cov=myapp --cov-report=term-missing tests/

# Fail under threshold
pytest --cov=myapp --cov-fail-under=80 tests/
```

## Configuration (pyproject.toml)

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
addopts = [
    "-v",
    "--cov=myapp",
    "--cov-report=term-missing",
]

[tool.coverage.run]
source = ["myapp"]
omit = ["*/tests/*", "*/migrations/*"]
branch = true

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "raise AssertionError",
    "raise NotImplementedError",
    "if TYPE_CHECKING:",
]
```

## CI integration

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.11", "3.12"]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
      - run: pip install -e ".[dev]" pytest pytest-cov
      - run: pytest --cov=myapp --cov-report=xml
      - uses: codecov/codecov-action@v4
        with:
          file: ./coverage.xml
```

## Markers

```python
import pytest, os

@pytest.mark.slow
def test_slow(): ...

@pytest.mark.integration
def test_db(): ...

@pytest.mark.skip(reason="not implemented")
def test_future(): ...

@pytest.mark.skipif(os.name == "nt", reason="unix only")
def test_unix(): ...

@pytest.mark.xfail(reason="known bug #123")
def test_known_bug(): assert False
```

```bash
pytest -m slow              # only slow
pytest -m "not slow"        # skip slow
pytest -m integration       # only integration
```

Register custom markers in `pyproject.toml` to avoid warnings:

```toml
[tool.pytest.ini_options]
markers = [
    "slow: marks tests as slow",
    "integration: marks integration tests",
    "unit: marks unit tests",
    "e2e: marks end-to-end tests",
]
```

## Tips

- Aim for **meaningful** coverage — high % with bad assertions is worthless.
- Branch coverage (`branch = true`) catches missed conditional paths.
- Use `# pragma: no cover` sparingly for code that's intentionally untestable.
