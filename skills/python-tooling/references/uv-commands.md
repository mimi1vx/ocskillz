# UV Commands Reference

uv is an extremely fast Python package manager and virtual environment tool written in Rust. It replaces pip, virtualenv, pip-tools, and more.

## Installation

```bash
# macOS/Linux (not recommended)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Via pip
pip install uv

# Via Homebrew
brew install uv
```

## Project Initialization

```bash
# Create new project
uv init myproject

# Create project in current directory
uv init .

# Create package (with src/ layout)
uv init --package mypackage
```

## Virtual Environments

```bash
# Create virtual environment in .venv (default)
uv venv

# Create with custom name
uv venv .myenv

# Create with specific Python version
uv venv --python 3.11
uv venv --python 3.12

# Activate (bash/zsh)
source .venv/bin/activate

# Activate (fish)
source .venv/bin/activate.fish

# Activate (Windows)
.venv\Scripts\activate

# Check Python version in venv
uv python version
```

## Dependency Management

```bash
# Add dependency
uv add requests

# Add with version specifier
uv add "requests>=2.28"

# Add dev dependency
uv add --group dev pytest

# Add optional dependency
uv add --optional httpx http

# Remove dependency
uv remove requests

# Sync all dependencies
uv sync

# Sync specific group
uv sync --group dev
```

## Running Commands

```bash
# Run with project venv (must be activated)
uv run python script.py
uv run pytest

# Run without venv (creates temp environment)
uv run --with requests python -c "import requests"

# Run with multiple temp packages
uv run --with requests --with rich python script.py
```

## Package Operations

```bash
# List installed packages
uv pip list

# List outdated packages
uv pip list --outdated

# Freeze requirements
uv pip freeze > requirements.txt

# Uninstall all packages
uv pip uninstall -r <(uv pip freeze)
```

## Python Version Management

```bash
# Find installed Python versions
uv python list

# Install Python version
uv python install 3.11
uv python install 3.12

# Run with specific Python
uv run --python 3.11 python script.py
```

## Build and Publish

```bash
# Build package
uv build

# Publish to PyPI
uv publish

# Publish to test PyPI
uv publish --test-pypi
```

## Advanced

```bash
# Cache management
uv cache clean
uv cache clean --old

# Show uv version
uv --version

# Self-update uv
uv self update
```

## Common Workflows

### New Project Setup
```bash
uv init myproject
cd myproject
uv venv
source .venv/bin/activate
uv add requests
uv add --group dev ruff ty pytest
```

### Existing Project
```bash
uv venv
source .venv/bin/activate
uv sync --all-groups
```

### One-off Script
```bash
uv run --with requests python script.py
```
