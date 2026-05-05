# Monorepo Setup with Bun Workspaces

Bun supports `workspaces` natively — no Lerna, no Nx required for small/medium monorepos.

## Layout

```
my-monorepo/
├── package.json          # workspace root
├── tsconfig.base.json    # shared compiler options
├── biome.json            # shared lint/format
├── bun.lock
└── packages/
    ├── core/
    │   ├── package.json
    │   ├── tsconfig.json
    │   └── src/
    ├── cli/
    │   ├── package.json
    │   ├── tsconfig.json
    │   └── src/
    └── web/
        ├── package.json
        ├── tsconfig.json
        └── src/
```

## Root `package.json`

```json
{
  "name": "my-monorepo",
  "private": true,
  "workspaces": ["packages/*"],
  "scripts": {
    "lint":      "biome check .",
    "fix":       "biome check --write .",
    "typecheck": "tsc --build",
    "test":      "bun test",
    "ci":        "bun run lint && bun run typecheck && bun run test"
  },
  "devDependencies": {
    "@biomejs/biome": "^1.9.0",
    "typescript": "^5.6.0",
    "bun-types": "latest"
  }
}
```

## Root `tsconfig.json`

```json
{
  "files": [],
  "references": [
    { "path": "./packages/core" },
    { "path": "./packages/cli" },
    { "path": "./packages/web" }
  ]
}
```

## Root `tsconfig.base.json`

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "composite": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  }
}
```

## Per-package `tsconfig.json`

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src/**/*"],
  "references": [
    { "path": "../core" }
  ]
}
```

## Per-package `package.json`

```json
{
  "name": "@my/cli",
  "version": "0.1.0",
  "type": "module",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "dependencies": {
    "@my/core": "workspace:*"
  }
}
```

The `workspace:*` protocol tells Bun to symlink the local package.

## Common workflow

```bash
# Install everything
bun install

# Add dep to a specific workspace
bun add zod --filter @my/core

# Run script in one workspace
bun --filter @my/cli run build

# Run script in all workspaces
bun run --filter "*" test

# Build all (incremental, project refs)
bunx tsc --build
```

## Tips

- One Biome config at the root; let it lint everything.
- One `tsconfig.base.json` at the root; each package extends it.
- Keep cross-package imports through declared dependencies — never reach into `../other-pkg/src` directly.
- For publish: use `bun publish` per package, or a tool like `changesets` for coordinated releases.
