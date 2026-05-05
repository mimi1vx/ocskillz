# Bun Commands

## Install Bun

```bash
curl -fsSL https://bun.sh/install | bash
# or via Homebrew
brew install oven-sh/bun/bun
```

## Project lifecycle

| Command                      | Purpose                                  |
|------------------------------|------------------------------------------|
| `bun init`                   | Scaffold a new project                   |
| `bun install`                | Install all deps from `package.json`     |
| `bun add <pkg>`              | Add runtime dependency                   |
| `bun add -d <pkg>`           | Add dev dependency                       |
| `bun add -g <pkg>`           | Global install                           |
| `bun remove <pkg>`           | Remove a dependency                      |
| `bun update [<pkg>]`         | Update one or all deps                   |
| `bun outdated`               | Show outdated deps                       |
| `bun pm ls`                  | List installed packages (tree)           |
| `bun pm cache rm`            | Clear package cache                      |

## Running code

| Command                    | Purpose                                                |
|----------------------------|--------------------------------------------------------|
| `bun run file.ts`          | Execute a TS/JS file directly                          |
| `bun file.ts`              | Same; `run` is implicit                                |
| `bun --watch run file.ts`  | Re-run on file change                                  |
| `bun --hot run file.ts`    | Hot reload (preserves state where possible)            |
| `bun run <script>`         | Run a `package.json` script                            |
| `bunx <pkg>`               | Like `npx`; runs a one-off package                     |

## Testing (built-in)

```bash
bun test                 # runs *.test.ts and *.spec.ts
bun test --watch
bun test --coverage
bun test path/to/file.test.ts
```

API is Jest-compatible:

```ts
import { test, expect, describe, beforeEach } from "bun:test";

describe("math", () => {
  test("adds", () => {
    expect(1 + 1).toBe(2);
  });
});
```

## Building

```bash
# Bundle for Bun runtime
bun build src/index.ts --outdir dist --target bun

# Bundle for Node
bun build src/index.ts --outdir dist --target node

# Bundle for browser, minified
bun build src/index.ts --outdir dist --target browser --minify
```

## Lockfile

- `bun.lock` (text format, recent versions) — commit it.
- Older `bun.lockb` (binary) — also commit if present, but prefer migrating to text.

## Performance flags worth knowing

- `--smol` — lower memory mode for constrained environments
- `--bun` — force Bun's transformer for compatible Node packages
