# Ty Configuration Reference

Ty is a fast, modern type checker from the Astral team (creators of ruff and uv). It's significantly faster than mypy and pyright.

## Installation

```bash
# Add to dev dependencies
uv add --group dev ty
```

## Basic Setup

Add to `pyproject.toml`:

```toml
[tool.ty.environment]
python-version = "3.11"

[tool.ty.terminal]
error-on-warning = true
```

## Running Ty

```bash
# Type check src directory
ty check src/

# Type check specific file
ty check src/my_module.py

# Watch mode
ty check src/ --watch

# Show detailed errors
ty check src/ --verbose
```

## Configuration Options

### Python Version

```toml
[tool.ty.environment]
python-version = "3.11"  # or "3.12", "3.13", "3.14"
```

### Strictness

```toml
[tool.ty.rules]
# Enable strict rules
possibly-unresolved-reference = "error"
unused-ignore-comment = "warn"

# Custom rule settings
any = "allow"  # or "warn", "error"
```

### Terminal Output

```toml
[tool.ty.terminal]
error-on-warning = true  # Exit with error if warnings exist
show-signature = true    # Show function signatures
show-docs = true         # Show docstrings in errors
```

## Ty vs Mypy vs Pyright

| Feature | ty | mypy | pyright |
|---------|-----|------|---------|
| Speed | Fastest | Slow | Fast |
| Language | Rust | Python | TypeScript |
| Built-in LSP | No | No | Yes |
| Stub packages | No | Yes | Yes |
| Configuration | pyproject.toml | mypy.ini | pyrightconfig.json |

## Common Rules

```toml
[tool.ty.rules]
# Missing type hints
missing-return = "warn"
missing-parameter = "warn"

# Type issues
possibly-unresolved-reference = "error"
unused-ignore-comment = "warn"

# Any type
any = "warn"
```

## Per-File Configuration

```toml
[tool.ty]
sources = ["src"]

[tool.ty.file-settings]
# Relax rules for tests
"tests/**/*.py" = { rules = { any = "allow" } }

# Ignore specific files
"**/migrations/*.py" = { exclude = true }
```

## CI Integration

```yaml
# GitHub Actions
- name: Type check
  run: uv run ty check src/
```

## Makefile Integration

```makefile
.PHONY: typecheck

typecheck:
	uv run ty check src/
```

## IDE Integration

### VS Code

Install the mypy extension (works with ty for basic checks):

```json
{
  "python.linting.tyEnabled": true,
  "python.linting.tyArgs": ["check", "src/"]
}
```

Note: Ty doesn't have a built-in LSP server. For real-time type checking in IDEs, consider using pyright or mypy with `--fast-exit`.

## Troubleshooting

### "No module named 'ty'"

```bash
# Ensure ty is installed
uv add --group dev ty

# Or run with uv run
uv run ty check src/
```

### Too many errors

Start with lenient settings:

```toml
[tool.ty.rules]
any = "allow"
```

Then gradually enable stricter rules.

### Slow performance

Ty is already fast. If slow:
- Check you're not running mypy simultaneously
- Use `--no-cache` to test raw performance

## Best Practices

1. **Enable early**: Add ty to new projects from day one
2. **Start strict**: Error on unresolved references
3. **Use `uv run`**: No need to activate venv
4. **CI check**: Run `ty check src/` in CI pipeline
5. **Fix warnings**: Set `error-on-warning = true`
