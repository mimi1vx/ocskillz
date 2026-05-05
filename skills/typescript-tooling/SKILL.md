---
name: typescript-tooling
description: Modern TypeScript tooling with Bun, Biome, and tsc. Covers project init with Bun, linting + formatting with Biome, type-checking with tsc, and monorepo setup. Use when starting or modernizing a TypeScript project.
license: MIT
metadata:
  language: typescript
  scope: tooling, package management, linting, formatting, type checking, monorepo
---

# TypeScript Tooling

Guide for modern TypeScript: **Bun** (runtime + package manager), **Biome** (lint + format), **tsc** (type checking).

## When to Use This Skill

- Starting a new TypeScript project
- Replacing `npm`/`yarn`/`pnpm` with Bun
- Replacing ESLint + Prettier with Biome
- Setting up `tsc --noEmit` as a CI gate
- Converting an existing project to a Bun-based monorepo (workspaces)

## When NOT to Use This Skill

- Project requires Node-only features Bun doesn't yet support (rare; check Bun's compat page).
- Team has strong investment in ESLint plugins not yet supported by Biome.
- Deno-only environments.

## Anti-Patterns to Avoid

| Avoid | Use Instead |
|-------|-------------|
| `npm install` | `bun add` |
| `npm run <script>` | `bun run <script>` (or `bun <script>`) |
| ESLint + Prettier + import-sort | Biome (single tool) |
| `ts-node` | `bun run file.ts` (native TS execution) |
| `nodemon` | `bun --watch run` |
| Mixing tabs and spaces, manual import sorting | Biome handles both |
| `tsc` to compile + run | `tsc --noEmit` for checks; let Bun execute |

## Decision Tree

```
What do you need?
│
├─ New project?
│   └─ bun init  →  see references/bun-commands.md
│
├─ Lint + format?
│   └─ Biome  →  see references/biome-config.md
│
├─ Type checking?
│   └─ tsc --noEmit  →  see references/tsc-config.md
│
└─ Multi-package repo?
    └─ Bun workspaces  →  see references/monorepo-setup.md
```

## Quick Start

```bash
# Install Bun
curl -fsSL https://bun.sh/install | bash

# New project
bun init -y
bun add -d @biomejs/biome typescript

# Initialize Biome config
bunx biome init

# First commands
bun run index.ts          # execute TS directly
bunx biome check .        # lint + format check
bunx biome check --write . # apply fixes
bunx tsc --noEmit         # type-check only
```

## Recommended `package.json` scripts

```json
{
  "scripts": {
    "dev":       "bun --watch run src/index.ts",
    "start":     "bun run src/index.ts",
    "build":     "bun build src/index.ts --outdir dist --target bun",
    "typecheck": "tsc --noEmit",
    "lint":      "biome check .",
    "fix":       "biome check --write .",
    "test":      "bun test",
    "ci":        "biome check . && tsc --noEmit && bun test"
  }
}
```

## Recommended `tsconfig.json` (modern, strict)

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ESNext"],
    "types": ["bun-types"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": true,
    "skipLibCheck": true,
    "noEmit": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"]
}
```

## Tool Overview

| Tool   | Purpose                          | Install                                 |
|--------|----------------------------------|-----------------------------------------|
| Bun    | Runtime + package manager + test | `curl -fsSL https://bun.sh/install \| bash` |
| Biome  | Lint + format + import sort      | `bun add -d @biomejs/biome`             |
| tsc    | Type checking only               | `bun add -d typescript`                 |

## Best Practices Checklist

- [ ] Use `bun` for install/run; commit `bun.lock`
- [ ] `tsc --noEmit` runs in CI (Bun executes; tsc only checks)
- [ ] Biome runs on pre-commit and in CI
- [ ] `strict: true` plus `noUncheckedIndexedAccess`
- [ ] No `any` outside test boundaries — use `unknown` and narrow
- [ ] Workspace setup uses Bun's native `workspaces` field

## References

- [bun-commands.md](./references/bun-commands.md) — install, run, add, test, build
- [biome-config.md](./references/biome-config.md) — biome.json, rule selection, ignore patterns
- [tsc-config.md](./references/tsc-config.md) — strict tsconfig, common pitfalls
- [monorepo-setup.md](./references/monorepo-setup.md) — Bun workspaces, shared configs

## Resources

- Bun: https://bun.sh/docs
- Biome: https://biomejs.dev/
- TypeScript: https://www.typescriptlang.org/docs/
