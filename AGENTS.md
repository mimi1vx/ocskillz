# Engineering preferences

These apply to all project work.

## Writing code (karpathy-guidelines)

- **Surgical changes.** Touch only what the request requires. Don't refactor,
  reformat, or "improve" adjacent code. Match existing style even if you'd do it
  differently. Every changed line must trace to the request. Clean up only the
  orphans your own change created; flag pre-existing dead code, don't delete it.
- **Simplicity first.** Ship the minimum that solves the problem. No speculative
  features, abstractions for single-use code, unrequested configurability, or
  error handling for impossible cases. If 200 lines could be 50, rewrite it.
- **Sparse comments.** Keep comments short and only where logic isn't obvious at
  a glance. Don't narrate self-evident code. Explain *why*, not *what*.
- **Think before coding.** Surface assumptions and ambiguities before writing.
  State a brief plan for multi-step work.
- **Goal-driven execution.** Turn tasks into verifiable success criteria and loop
  until they pass. "Fix the bug" → "write a test that reproduces it, then make it
  pass." "Refactor X" → "tests pass before and after."

## Debugging (debug-loop)

Reproduce → isolate → hypothesize → write a failing test → fix (smallest change)
→ verify (test passes, no regression) → document. State the hypothesis
precisely; if you can't articulate the cause, you don't understand it yet — keep
isolating. Don't fix by guessing.

## Commits (git-commit)

- **Conventional Commits**, WHY over WHAT — the diff already shows what changed;
  the message must explain why. Types: `feat`, `fix`, `docs`, `style`,
  `refactor`, `test`, `chore`, `perf`, `ci`.
- Only commit when asked. Inspect `git status` / `git diff` / recent `git log`
  first; stage only intended files; never commit secrets. Match the repo's
  existing message style.

## Before a PR (pr-review)

Check diff scope, breaking changes, and test-coverage delta. Ensure lint / type /
test gates pass locally. Self-review the diff before asking anyone else to.

## Tooling defaults

- **Python:** `uv` (venv + deps), `ruff` (lint + format), `ty` (types). Not
  pip/venv, black/flake8/isort, or mypy.
- **TypeScript:** `bun` (runtime + deps + test), `biome` (lint + format), `tsc
  --noEmit` (types). Not npm, ESLint+Prettier, or ts-node.
- **Haskell:** `cabal` (build + deps), `hlint` (lint), `ghc --make` (compile). Not stack or ghcide.
- **Perl:** `cpanfile` + current `cpm` (deps), `perltidy` (format), a curated
  `Perl::Critic` profile (lint), and `prove`/Test2 (tests) for new projects.
  Preserve established Carton/Carmel/cpanm and authoring workflows.
- **Rust:** `cargo` (build + deps + test), `rustfmt` (format), `clippy` (lint). Not rustup.
- **Shell:** `shfmt` (format), `shellcheck` (lint).
- Respect a project's existing toolchain when it differs — match what's there
  rather than migrating unasked.

## Tone

Be direct and objective. Prioritize technical accuracy over agreement; disagree
and correct when warranted. No filler praise. Concise output.
