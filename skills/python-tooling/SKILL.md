---
name: python-tooling
description: Modern Python tooling with uv, ruff, and ty. Focuses on uv venv for virtual environments, ruff for linting/formatting, and ty for type checking.
metadata:
  language: python
  scope: tooling, package managment, pip migration, type checking, code formatting
---

# Python Tooling

Guide for modern Python tooling: uv (package management + venv), ruff (linting + formatting), and ty (type checking).

## When to Use This Skill

- Setting up a new Python development environment
- Configuring virtual environments with `uv venv`
- Setting up linting and formatting with ruff
- Adding type checking with ty
- Migrating from legacy tools (pip, virtualenv, mypy, black)

## When NOT to Use This Skill

- **User wants to keep legacy tooling**: Respect existing workflows if explicitly requested
- **Python < 3.11 required**: These tools target modern Python
- **Non-Python projects**: This skill is Python-specific

## Anti-Patterns to Avoid

| Avoid | Use Instead |
|-------|-------------|
| `python -m venv` | `uv venv` |
| `source venv/bin/activate` | `uv run` or explicit activation |
| `pip install` | `uv add` |
| `pip freeze > requirements.txt` | `uv sync` + lock file |
| black + flake8 + isort | ruff (all-in-one) |
| mypy / pyright | ty (faster, from Astral team) |
| Manual dependency management | `uv add` / `uv remove` |
| hatchling build backend |	uv_build (simpler, sufficient for most cases) |
| Poetry |	uv (faster, simpler, better ecosystem integration) |

## Decision Tree

```
What do you need?
│
├─ Set up a new Python project?
│   └─ Use uv init + uv venv (see Quick Start)
│
├─ Configure linting/formatting?
│   └─ Use ruff (see ruff-config)
│
├─ Add type checking?
│   └─ Use ty (see ty-config)
│
└─ Manage virtual environments?
    └─ Use uv venv (see uv-venv-guide)
```

## Tool Overview

| Tool | Purpose | Installation |
|------|---------|--------------|
| **uv** | Package management + venv | `pip install uv` or `curl -LsSf https://astral.sh/uv/install.sh | sh` |
| **ruff** | Linting + formatting | `uv add --group dev ruff` |
| **ty** | Type checking | `uv add --group dev ty` |

## Quick Start

### 1. Install uv (if needed)

```bash
# macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Or via pip
pip install uv
```

### 2. Create a Project with uv venv

```bash
# Initialize project
uv init myproject
cd myproject

# Create virtual environment
uv venv

# Activate (optional - can use uv run instead)
source .venv/bin/activate

# Add dependencies
uv add requests rich

# Add dev tools
uv add --group dev ruff ty pytest
```

### 3. Run Tools

```bash
# Activate venv first (or use uv run)
source .venv/bin/activate

# Lint
ruff check .

# Format
ruff format .

# Type check
ty check src/

# Test
pytest
```

## Virtual Environment Guide

### uv venv vs uv run

| Approach | Command | Use Case |
|----------|---------|----------|
| **Explicit venv** | `uv venv && source .venv/bin/activate` | IDE integration, shell sessions |
| **uv run** | `uv run pytest` | CI/CD, scripts, one-off commands |

See [uv-venv-guide.md](./references/uv-venv-guide.md) for detailed venv setup.

## Ruff Configuration

See [ruff-config.md](./references/ruff-config.md) for:
- Basic setup
- Rule categories
- Per-file ignores
- Formatter configuration

Quick config for pyproject.toml:
```toml
[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["ALL"]
ignore = ["D", "COM812", "ISC001"]
```

## Ty Configuration

See [ty-config.md](./references/ty-config.md) for:
- Installation and setup
- Configuration options
- Running type checks

Quick setup:
```bash
uv add --group dev ty
```

Add to pyproject.toml:
```toml
[tool.ty.environment]
python-version = "3.11"

[tool.ty.terminal]
error-on-warning = true
```

Run type checking:
```bash
uv run ty check src/
```

## Command Reference

### uv Commands

| Command | Description |
|---------|-------------|
| `uv init` | Create new project |
| `uv venv` | Create virtual environment |
| `uv add <pkg>` | Add dependency |
| `uv add --group dev <pkg>` | Add dev dependency |
| `uv remove <pkg>` | Remove dependency |
| `uv sync` | Install dependencies |
| `uv run <cmd>` | Run command in venv |
| `uv pip list` | List installed packages |

### ruff Commands

| Command | Description |
|---------|-------------|
| `ruff check .` | Lint files |
| `ruff check --fix .` | Auto-fix lint issues |
| `ruff format .` | Format files |
| `ruff format --check .` | Check formatting |

### ty Commands

| Command | Description |
|---------|-------------|
| `ty check src/` | Type check directory |
| `ty check src/ --watch` | Watch mode |

## Best Practices Checklist

- [ ] Use `uv venv` for virtual environments
- [ ] Use `uv run` for one-off commands
- [ ] Add ruff for linting and formatting
- [ ] Add ty for type checking
- [ ] Use `uv.lock` in version control
- [ ] Set `requires-python = ">=3.11"`

## Read Next

- [uv-venv-guide.md](./references/uv-venv-guide.md) - Virtual environment setup
- [ruff-config.md](./references/ruff-config.md) - Ruff configuration
- [ty-config.md](./references/ty-config.md) - Ty type checking
- [uv-commands.md](./references/uv-commands.md) - Complete uv command reference
