# Biome Configuration

Biome replaces ESLint + Prettier + import-sort with one fast tool.

## Install

```bash
bun add -d @biomejs/biome
bunx biome init   # creates biome.json
```

## Recommended `biome.json`

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.0/schema.json",
  "vcs": {
    "enabled": true,
    "clientKind": "git",
    "useIgnoreFile": true
  },
  "files": {
    "ignoreUnknown": true,
    "ignore": ["dist", "node_modules", "coverage", "*.min.js"]
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100,
    "lineEnding": "lf"
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "double",
      "semicolons": "always",
      "trailingCommas": "all",
      "arrowParentheses": "always"
    }
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "correctness": {
        "noUnusedVariables": "error",
        "noUnusedImports": "error"
      },
      "style": {
        "useImportType": "error",
        "useNodejsImportProtocol": "error"
      },
      "suspicious": {
        "noExplicitAny": "warn"
      }
    }
  },
  "organizeImports": {
    "enabled": true
  }
}
```

## Common Commands

```bash
bunx biome check .            # lint + format check (no writes)
bunx biome check --write .    # apply safe fixes
bunx biome check --write --unsafe .   # also apply potentially-breaking fixes
bunx biome format --write .   # format only
bunx biome lint .             # lint only
bunx biome ci .               # CI mode (no writes, structured output)
```

## Per-file overrides

```json
{
  "overrides": [
    {
      "include": ["**/*.test.ts", "**/*.spec.ts"],
      "linter": {
        "rules": {
          "suspicious": { "noExplicitAny": "off" }
        }
      }
    },
    {
      "include": ["scripts/**"],
      "linter": {
        "rules": {
          "style": { "useNodejsImportProtocol": "off" }
        }
      }
    }
  ]
}
```

## Editor integration

- VS Code: install `biomejs.biome` extension, set as default formatter.
- Pre-commit: use `lefthook` or `husky` to run `biome check --write --staged`.

## Migration from ESLint + Prettier

```bash
bunx biome migrate eslint --write
bunx biome migrate prettier --write
```

These read your existing `.eslintrc` / `.prettierrc` and translate equivalent rules into `biome.json`.
