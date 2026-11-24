# 01 — Tooling & Project Setup

Runtime, package manager, module format, type gate, and lint gate. These
decisions are made once and paid for daily; almost every "TypeScript is
painful" complaint traces back to a wrong choice here.

Config keys and CLI flags in this file move across major versions. Verify
against the primary references in `SKILL.md` before asserting that a project's
config is wrong.

## 1.1 Runtime and package manager

New projects default to **Bun** — runtime, package manager, bundler, and test
runner in one binary, with native TypeScript execution and no build step in
development. Established projects keep what they have.

| Situation | Use |
|---|---|
| New service, CLI, or library | Bun |
| Existing Node project | Node; do not migrate unasked |
| Deployment target only ships Node (many PaaS, Lambda runtimes, vendor images) | Node runtime; Bun is still fine as the local package manager if the team wants it |
| Native addons, or a dependency that probes `process.binding`/internal Node APIs | Node |
| Existing Deno project, or a permissions-first sandbox requirement | Deno |

Rules:

- **The runtime is a deployment fact, not a preference.** Check the Dockerfile,
  CI image, and hosting target before recommending Bun; "works on my machine
  with Bun" and "the image runs `node dist/index.js`" is a real incident.
- **One package manager per repository.** Multiple lockfiles (`bun.lock` and
  `package-lock.json` side by side) means two different dependency graphs and
  two different CI results. Pick one, delete the others, and enforce it.
- Do not mix `npx` and `bunx` in scripts; use the repo's own.

### Everyday commands

| Command | Purpose |
|---|---|
| `bun init` | scaffold `package.json` + `tsconfig.json` |
| `bun install` / `bun install --frozen-lockfile` | install; the frozen form is the CI form |
| `bun add <pkg>` / `bun add -d <pkg>` | runtime / dev dependency |
| `bun remove`, `bun update`, `bun outdated` | dependency lifecycle |
| `bun run <script>` | run a `package.json` script |
| `bun run file.ts` | execute TypeScript directly — no build, no `ts-node` |
| `bun --watch run file.ts` | restart on change (`--hot` reloads in place, keeping state) |
| `bunx <pkg>` | one-off package execution |
| `bun build <entry> --outdir dist --target <bun\|node\|browser>` | bundle |

## 1.2 `package.json` anatomy

```jsonc
{
  "name": "@scope/pkg",
  "version": "0.1.0",
  "type": "module",              // ESM. Omitting this means CJS — decide, don't drift.
  "engines": { "node": ">=22" }, // the floor you actually test
  "exports": {                   // the public surface; supersedes "main"
    ".": "./dist/index.js",
    "./package.json": "./package.json"
  },
  "files": ["dist"],             // what gets published; everything else stays local
  "sideEffects": false,          // enables tree-shaking for consumers — only if true
  "scripts": {
    "dev": "bun --watch run src/index.ts",
    "build": "bun build src/index.ts --outdir dist --target bun",
    "typecheck": "tsc --noEmit",
    "lint": "biome check .",
    "fix": "biome check --write .",
    "test": "bun test",
    "ci": "bun run lint && bun run typecheck && bun run test"
  }
}
```

- **`exports` is an encapsulation boundary.** Once declared, consumers cannot
  reach into `dist/internal/*`. Declaring only `main` leaves your entire file
  tree public and every internal path a de-facto API.
- **Always export `./package.json`.** Tooling reads it through the resolver.
- **`sideEffects: false` is a claim.** If any module mutates globals, registers
  a polyfill, or installs a handler at import time, the claim is false and
  bundlers will delete code you needed.
- **`engines` must match CI.** An `engines` floor nobody tests is decoration.

## 1.3 The canonical `tsconfig.json`

One base config per repository. Everything else `extends` it and declares only
its delta (1.8). This is the Bun-targeted baseline; for Node, drop the Bun
`types` entry and set `module`/`moduleResolution` to match your bundler or
`nodenext`.

```jsonc
{
  "compilerOptions": {
    // Environment
    "target": "ESNext",
    "lib": ["ESNext"],
    "module": "Preserve",          // emit-free; let the runtime/bundler decide
    "moduleResolution": "bundler",
    "moduleDetection": "force",    // every file is a module; no accidental globals
    "types": ["bun"],              // requires: bun add -d @types/bun
    "allowImportingTsExtensions": true,

    // Correctness (the floor)
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,

    // Module hygiene
    "isolatedModules": true,
    "verbatimModuleSyntax": true,

    // Interop
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

Why the non-obvious ones (full rationale for the type-level flags is in
`rules/02`):

| Flag | Buys you |
|---|---|
| `noUncheckedIndexedAccess` | `arr[i]` is `T \| undefined`; the single highest-value strictness flag beyond `strict` |
| `moduleDetection: force` | No file silently becomes a script with global scope |
| `verbatimModuleSyntax` | Type-only imports must say `import type`; required for correct erasure by fast transpilers |
| `isolatedModules` | Every file transpiles alone — the assumption every non-`tsc` toolchain makes |
| `allowImportingTsExtensions` | Lets you write the real specifier (`./x.ts`) that Bun and Deno resolve |
| `skipLibCheck` | Skips checking `.d.ts` of dependencies. Pragmatic and near-universal, but it *does* hide broken vendor types; drop it if you are debugging a types mismatch |

**`@types/bun`, not `bun-types`.** The `types` array must name `bun` on current
TypeScript majors.

## 1.4 Type-checking is a separate gate

Bun, esbuild, swc, Vite, and every other fast toolchain **strip types without
checking them**. A green build says nothing about type correctness.

- `tsc --noEmit` runs in CI, always, as its own step.
- Locally: `bunx tsc --noEmit --watch` in a second terminal, or the editor's
  workspace TypeScript version — not the build output.
- If the build emits declaration files, `tsc` is also the emitter for those and
  needs `declaration: true` on a separate emitting config (1.8).

A repository whose CI runs `bun build` and `bun test` but never `tsc --noEmit`
is shipping unchecked types. That is a MEDIUM finding on its own and the root
cause of many HIGH ones.

## 1.5 Lint and format: one tool, enforced

**Biome** for new projects: lint, format, and import sorting in one binary with
one config. Migrate an existing setup only on request:

```bash
bunx biome migrate eslint --write
bunx biome migrate prettier --write
```

Biome's major versions break config. On v2 the keys are `files.includes` (a
single list, with `!` negation — `files.ignore`/`include` are gone), and import
sorting lives under `assist.actions.source.organizeImports`, not a top-level
`organizeImports`. Globs are relative to the config file and `*` no longer
crosses `/`. `biome migrate --write` performs the upgrade; run it rather than
hand-editing.

```jsonc
{
  "$schema": "https://biomejs.dev/schemas/2.0.0/schema.json",
  "vcs": { "enabled": true, "clientKind": "git", "useIgnoreFile": true },
  "files": { "includes": ["**", "!dist/**", "!coverage/**", "!**/*.min.js"] },
  "formatter": { "indentStyle": "space", "indentWidth": 2, "lineWidth": 100 },
  "javascript": { "formatter": { "quoteStyle": "double", "semicolons": "always" } },
  "linter": {
    "rules": {
      "recommended": true,
      "correctness": { "noUnusedVariables": "error", "noUnusedImports": "error" },
      "style": { "useImportType": "error", "useNodejsImportProtocol": "error" },
      "suspicious": { "noExplicitAny": "error" }
    }
  },
  "assist": { "actions": { "source": { "organizeImports": "on" } } }
}
```

- **Enforced means CI**, not just the editor. `biome ci .` in the pipeline;
  editor integration and a pre-commit hook are conveniences on top.
- **Do not exempt tests from the lint rules.** A `*.test.ts` override that
  disables `noExplicitAny` creates a second, weaker standard for code that is
  supposed to be the safety net (`rules/07`, `sota-testing`).
- ESLint remains correct for projects that need type-aware rules Biome does not
  yet implement. That is a reason to stay, not a defect.

## 1.6 `bunfig.toml`

Runtime and test configuration that does not belong in `package.json`:

```toml
[install]
frozenLockfile = true          # in CI; fail instead of silently resolving

[test]
preload = ["./test/setup.ts"]  # global fixtures/matchers
coverage = true
coverageReporter = ["text", "lcov"]
coveragePathIgnorePatterns = ["src/generated/**"]
```

Coverage thresholds (`coverageThreshold`) exist and fail the run when unmet.
Use them as a **ratchet**, not a target: store the current measured value and
raise it, never pick a round number to hit. The reasoning is in `sota-testing`
rules/07 §7.2; the mechanics are in `rules/07` of this skill.

## 1.7 Lockfiles and reproducible installs

- **Commit the lockfile.** `bun.lock` (text) is the current format; older
  `bun.lockb` is binary — migrate it so diffs are reviewable.
- **CI installs frozen**: `bun install --frozen-lockfile` (or `npm ci`,
  `pnpm install --frozen-lockfile`). A CI that lets the resolver drift is not
  testing the artifact you ship, and it silently absorbs dependency
  substitutions (`rules/05`).
- **Lockfile changes are reviewed.** A dependency-bump PR whose diff nobody
  reads is the delivery mechanism for most supply-chain compromises.
- Never commit two lockfiles for two package managers (1.1).

## 1.8 Monorepos: workspaces, catalogs, project references

```jsonc
// root package.json
{
  "private": true,
  "workspaces": ["packages/*"],
  "scripts": {
    "typecheck": "tsc --build",
    "lint": "biome check .",
    "test": "bun test",
    "ci": "bun run lint && bun run typecheck && bun run test"
  }
}
```

- **Local packages depend on each other via `workspace:*`**, which resolves to
  a symlink locally and is rewritten to a real version on publish.
- **Shared versions go in a catalog** rather than being repeated in every
  package, so one edit moves the whole repo.
- **One `tsconfig.base.json` at the root; packages extend it** and add only
  `outDir`, `rootDir`, `composite`/`declaration`, and their `references`. Never
  restate the strictness flags — that is exactly how the strict baseline decays
  in the packages nobody looks at.

```jsonc
// packages/cli/tsconfig.json — the whole file
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": { "outDir": "dist", "rootDir": "src", "composite": true },
  "include": ["src/**/*"],
  "references": [{ "path": "../core" }]
}
```

- **Project references** (`composite: true` + `tsc --build`) give incremental,
  correctly-ordered type-checking across packages. Without them, monorepo type
  checks re-do all the work on every run.
- **One lint config at the root** lints everything.
- **Cross-package imports go through declared dependencies**, never
  `../other-pkg/src`. Reaching across the filesystem defeats the build graph
  and breaks publishing.
- Install and run scripts across selected packages with the package manager's
  filter flag; to add a dependency to a single package, run the add command
  from that package's directory.

## 1.9 Build and publish

- **Applications**: bundle with an explicit target (`--target bun`, `node`, or
  `browser`); pin it, because the default changes what globals exist.
- **Libraries**: publish ESM, ship `.d.ts` (emitted by `tsc`, not the bundler),
  declare `exports`, `files`, and `sideEffects`, and test the published tarball
  contents before release rather than after.
- Do not publish source-only TypeScript to consumers who cannot compile it, and
  do not publish `dist` without types.

## 1.10 The CI gate shape

Fastest, highest-signal first — the ordering rationale is `sota-testing`
rules/07 §7.5:

```
install (frozen) → lint/format check → tsc --noEmit → unit tests → integration → build
```

Each is a separate step so the failure name tells you what broke. A single
`bun run ci` chain is fine locally; in CI, separate steps give separate
diagnostics.

## 1.11 Suppressions must fail when they go stale

A suppression comment outlives the problem it hid. Once the code is fixed,
the comment silently pre-excuses the next real defect on that line. Make each
tool report unused suppressions **as a CI failure**, not a note in the log.

| Tool | Unused-suppression behavior | Make it fail CI |
|---|---|---|
| TypeScript | `// @ts-expect-error` reports `Unused '@ts-expect-error' directive` when no error follows; `// @ts-ignore` never reports | Use `@ts-expect-error` only; `tsc --noEmit` is already the gate (§1.4) |
| Biome | `// biome-ignore …` (also `-all`, `-start`/`-end`) that suppresses nothing emits a **warning**-level `suppressions/unused` diagnostic | `biome ci --error-on-warnings .` |
| ESLint | `linterOptions.reportUnusedDisableDirectives` reports `eslint-disable` comments that suppress nothing; the documented default is `"warn"` | set it to `"error"` in `eslint.config.js`, or pass `--report-unused-disable-directives-severity error` |

- **A warning does not fail a run by default** in either linter (ESLint also
  needs `--max-warnings 0` to turn warnings into a failure). Set the severity
  or the flag explicitly; relying on the default leaves stale suppressions
  green.
- Every suppression carries a reason: `// biome-ignore lint/rule: why`,
  `// eslint-disable-next-line rule -- why`, `// @ts-expect-error why`.
- Prefer a scoped config override for a whole class of files (generated code)
  over a per-line comment repeated across the tree.

## Audit checklist

- [ ] Stale suppressions can pass CI: `rg -n 'error-on-warnings' .github/ package.json`
      (Biome) and `rg -n 'reportUnusedDisableDirectives|report-unused-disable' eslint.config.* .github/ package.json`
      (ESLint); suppression comments present
      (`rg -c 'biome-ignore|eslint-disable|@ts-ignore'`) with neither gate →
      MEDIUM. `@ts-ignore` present anywhere → see `rules/02` checklist.
- [ ] Two package managers? `ls` for `bun.lock`, `package-lock.json`,
      `pnpm-lock.yaml`, `yarn.lock` in one repo → HIGH (divergent graphs).
- [ ] Is the type gate in CI? `rg -n 'tsc --noEmit|tsc --build' .github/ package.json`
      — absent while a bundler runs → MEDIUM (types never checked).
- [ ] Is lint enforced in CI, not just the editor?
      `rg -n 'biome (ci|check)|eslint' .github/` → absent → LOW–MEDIUM.
- [ ] Frozen installs in CI? `rg -n 'frozen-lockfile|npm ci|frozenLockfile' .github/ bunfig.toml`
      — plain `install` in CI → HIGH.
- [ ] Lockfile committed? Missing from the repo → HIGH.
- [ ] Strictness drift: `rg -n '"strict"|noUncheckedIndexedAccess' --glob 'tsconfig*.json'`
      across all packages; any config setting `"strict": false` or omitting the
      base `extends` → MEDIUM each.
- [ ] Duplicated compiler options instead of `extends`? Multiple tsconfigs
      restating `target`/`lib`/`strict` → LOW, and MEDIUM if they disagree.
- [ ] Stale Bun types: `rg -n 'bun-types' .` → LOW (should be `@types/bun` with
      `"types": ["bun"]`).
- [ ] Biome config on the previous major: `rg -n '"organizeImports"|"ignore"\s*:|schemas/1\.' biome.json*`
      → MEDIUM (run `biome migrate --write`).
- [ ] Test-only lint amnesty: `rg -n -A5 '\*\.test\.|\*\.spec\.' biome.json* .eslintrc*`
      disabling rules → MEDIUM (`rules/07`).
- [ ] Library packaging: `rg -n '"exports"|"files"|"types"' package.json` in
      published packages — missing `exports` → MEDIUM (whole tree is public API);
      missing `.d.ts` → HIGH for a TS consumer.
- [ ] `sideEffects: false` with import-time mutation? Cross-check against
      `rg -n 'globalThis\.|process\.on\(|\.prototype\.' src/` → MEDIUM.
- [ ] Monorepo reaching across packages:
      `rg -n "from ['\"]\.\./\.\./[^'\"]*/src/" packages/` → MEDIUM.
- [ ] Monorepo without project references while type checks are slow:
      no `composite`/`references` and a full re-check per run → LOW–MEDIUM.
