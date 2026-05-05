# tsc Configuration

When using Bun, `tsc` is **only** for type checking. Bun runs `.ts` directly.

## Strict modern `tsconfig.json`

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
    "noPropertyAccessFromIndexSignature": true,

    "isolatedModules": true,
    "verbatimModuleSyntax": true,

    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "skipLibCheck": true,

    "noEmit": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "coverage"]
}
```

## Why each flag matters

| Flag | Catches |
|------|--------|
| `strict` | Bundle of strict-* flags. Always on. |
| `noUncheckedIndexedAccess` | `arr[i]` becomes `T \| undefined` — forces handling holes. |
| `noImplicitOverride` | `override` keyword required when overriding methods. |
| `verbatimModuleSyntax` | Forces `import type` for type-only imports. Required for fast bundlers. |
| `isolatedModules` | Each file must be transpilable in isolation (Bun, esbuild requirement). |
| `noPropertyAccessFromIndexSignature` | Forces `obj["dyn"]` for index-signature keys; safer. |

## Running

```bash
bunx tsc --noEmit          # one-shot check
bunx tsc --noEmit --watch  # watch mode

# CI gate:
bun run typecheck
```

## Common pitfalls

- **Forgetting `import type`** with `verbatimModuleSyntax: true` → build errors. Fix: `import type { Foo } from "...";`.
- **`any` leaking from third-party libs** → install `@types/...` or write a `.d.ts` shim.
- **`tsc` building output** when you only wanted to check → ensure `noEmit: true`.
- **Slow type checks in monorepos** → use project references (`composite: true`, `references: [...]`).

## Project references for monorepos

Each package has its own `tsconfig.json` with `"composite": true`. Root `tsconfig.json`:

```json
{
  "files": [],
  "references": [
    { "path": "./packages/core" },
    { "path": "./packages/cli" }
  ]
}
```

Run incremental builds with `bunx tsc --build`.
