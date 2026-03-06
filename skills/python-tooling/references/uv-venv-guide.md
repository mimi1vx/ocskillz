# UV Virtual Environment Guide

This guide covers virtual environment management with `uv venv` - creating, activating, and managing Python virtual environments.

## Why uv venv?

| Feature | uv venv | python -m venv |
|---------|---------|----------------|
| Speed | ~50ms | ~500ms |
| Auto-discovery | Yes | No |
| Python auto-install | Yes | No |

## Basic Setup

### Create venv

```bash
# Create in default .venv location
uv venv

# Create with custom name
uv venv .myenv

# Create with specific Python
uv venv --python 3.11
uv venv --python 3.12
```

### Activate

```bash
# Bash/Zsh
source .venv/bin/activate

# Fish
source .venv/bin/activate.fish

# PowerShell
.venv\Scripts\Activate.ps1

# Windows CMD
.venv\Scripts\activate.bat
```

### Verify

```bash
# Check venv is active
which python3  # Should show .venv/bin/python3

# Check Python version
python333 --version
```

## Two Workflows

### Workflow 1: Explicit Activation

Best for: IDE integration, long-running development sessions

```bash
# Create and activate
uv venv
source .venv/bin/activate

# Install dependencies
uv add requests
uv add --group dev ruff ty pytest

# Run commands (no prefix needed)
ruff check .
python3 -m pytest
ty check src/

# Deactivate when done
deactivate
```

### Workflow 2: uv run

Best for: CI/CD, one-off commands, scripts

```bash
# No activation needed
uv run pytest
uv run ruff check .
uv run ty check src/

# With temporary dependencies
uv run --with requests python script.py
```

## .python-version File

Create `.python-version` in project root to auto-select Python version:

```bash
# Create file with version
echo "3.11" > .python-version

# Now uv venv uses this version automatically
uv venv

# Can verify
uv python version
```

## Project Structure

```
myproject/
├── .python-version      # Python version (optional)
├── pyproject.toml      # Project config
├── uv.lock             # Lock file
├── .venv/              # Virtual environment (created by uv venv)
└── src/
    └── myproject/
        └── __init__.py
```

## IDE Integration

### VS Code

```bash
# Create venv first
uv venv

# Then in VS Code
# Select interpreter: .venv/bin/python
```

Or add to `.vscode/settings.json`:
```json
{
  "python.venvPath": ".",
  "python.defaultInterpreterPath": ".venv/bin/python"
}
```

## Troubleshooting

### "No Python found"

```bash
# Install Python via uv
uv python install 3.11

# Or check system Python
which python3
```

### Wrong Python version

```bash
# Check current venv Python
uv python version

# Recreate with correct version
rm -rf .venv
uv venv --python 3.12
```

### Activation not working

```bash
# Verify venv exists
ls -la .venv/bin/

# Check shell
echo $SHELL
```

## CI/CD Integration

### GitHub Actions

```yaml
- name: Setup uv
  uses: astral-sh/setup-uv@v4

- name: Create venv
  run: uv venv

- name: Install dependencies
  run: uv sync --all-groups

- name: Run tests
  run: uv run pytest
```

### Docker

```dockerfile
FROM python:3.11-slim

# Install uv
RUN pip install uv

WORKDIR /app

# Create venv and install deps
RUN uv venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

RUN uv add requests
```

## Best Practices

1. **Commit `.python-version`** - Ensures team uses same Python version
2. **Commit `uv.lock`** - Reproducible builds
3. **Use `uv run` in CI** - No activation needed
4. **Add `.venv/` to `.gitignore`** - Don't commit venvs
5. **Use `--group dev`** - Separate dev dependencies
