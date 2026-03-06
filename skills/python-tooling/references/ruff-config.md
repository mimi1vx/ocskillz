# Ruff Configuration Reference

Ruff is an extremely fast Python linter and formatter written in Rust. It replaces flake8, black, isort, pyupgrade, and more.

## Installation

```bash
# Add to dev dependencies
uv add --group dev ruff
```

## Basic Setup

Add to `pyproject.toml`:

```toml
[tool.ruff]
line-length = 100
target-version = "py311"
src = ["src"]

[tool.ruff.lint]
select = ["ALL"]
ignore = [
    "D",        # pydocstyle
    "COM812",   # trailing comma conflict
    "ISC001",   # string concat conflict
]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
docstring-code-format = true
```

## Running Ruff

```bash
# Lint
ruff check .

# Auto-fix
ruff check --fix .

# Format
ruff format .

# Check formatting
ruff format --check .
```

## Rule Categories

| Code | Category |
|------|----------|
| E, W | pycodestyle |
| F | Pyflakes |
| I | isort |
| N | pep8-naming |
| D | pydocstyle |
| UP | pyupgrade |
| B | flake8-bugbear |
| S | flake8-bandit |
| PL | Pylint |

## Common Ignores

```toml
ignore = [
    "D",        # Docstrings
    "ANN401",   # Dynamically typed Any
    "TD002",    # Missing TODO author
    "COM812",   # trailing comma
    "ISC001",   # string concat
]
```

## Per-File Ignores

```toml
[tool.ruff.lint.per-file-ignores]
"tests/**/*.py" = ["S101", "ANN", "D"]
"scripts/**/*.py" = ["T20", "INP001"]
"__init__.py" = ["F401"]
"**/migrations/*.py" = ["ALL"]
```

## Migration from Other Tools

### From flake8
Remove flake8 and use ruff.

### From black
Remove black, use `ruff format`.

### From isort
Remove isort, ruff handles import sorting.
