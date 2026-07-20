# 01 - Tooling, Projects, and Dependencies

A Haskell build is defined by its compiler, package description, solver input,
dependency index, flags, and native environment. Make those inputs inspectable
and reproducible without replacing a healthy repository's established workflow.

## 1. Preserve working tooling; use GHCup and Cabal for greenfield work

For a new conventional project, install GHC and `cabal-install` with GHCup and
use Cabal for build, test, documentation, benchmark, and source-distribution
tasks. Cabal is the package format and build interface expected by Hackage; one
toolchain avoids duplicated project metadata.

```bash
ghcup install ghc latest
ghcup set ghc latest
ghcup install cabal latest
ghc --version
cabal --version
cabal update
cabal build all
```

Resolve `recommended` or the current stable release from live GHCup/GHC release
metadata when creating or maintaining automation. Do not copy a version called
"latest" from this document. GHC 9.14.1 is a dated July 2026 example only; it
must not become a permanent recommendation or an accidental support promise.

- GHCup manages user toolchains; it does not define project dependencies or make
  builds reproducible by itself. Record compiler selection in CI/deployment.
- Prefer Cabal over introducing Stack or Nix in a greenfield repository unless
  a concrete deployment, organization, or hermetic-build requirement selects
  another tool.
- Preserve established Stack, Nix, Bazel, distro-package, or custom workflows
  when they are maintained and reproducible. Migration requires an explicit
  benefit and parity for CI, release, developer, and platform behavior.
- Never run an unaudited remote installer with `curl | sh`. Follow GHCup's
  documented installation and verification guidance for the target platform.

## 2. Keep one authoritative package description

Use a `.cabal` file as the package's authoritative component and dependency
description. A minimal library plus executable makes ownership explicit:

```cabal
cabal-version:      3.0
name:               ledger-tool
version:            0.1.0.0
build-type:         Simple

common warnings
  ghc-options:      -Wall
  default-language: GHC2024

library
  import:           warnings
  exposed-modules:  Ledger
  hs-source-dirs:   src
  build-depends:
      base >=4.20 && <5
    , text >=2.0 && <2.2

executable ledger-tool
  import:           warnings
  main-is:          Main.hs
  hs-source-dirs:   app
  build-depends:
      base
    , ledger-tool
```

- Declare every direct dependency in the component that imports it. Do not rely
  on transitive packages being visible.
- Keep reusable domain code in a library and the executable entry point thin.
  Use an internal library when several private components genuinely share code.
- `exposed-modules` is public API. Put implementation modules in
  `other-modules`; Cabal's missing-home-modules warning should be clean.
- Use `common` stanzas for genuinely shared settings, not to hide which
  component depends on what.
- Prefer `build-type: Simple`. `Custom` and `Setup.hs` execute build code and
  need a specific requirement and supply-chain review.
- Keep generated `.cabal` workflows only where already established. If using
  hpack or another generator, identify the source of truth and check generated
  drift in CI; never hand-edit both representations.

## 3. Use cabal.project for workspace and solver policy

The package file states what a package can build with. `cabal.project` selects
the local workspace and project-wide solver inputs:

```cabal
packages: .
index-state: 2026-07-01T00:00:00Z

package ledger-tool
  tests: True
  benchmarks: True
```

- Include all local packages explicitly. Avoid broad globs that silently admit
  generated or vendored packages.
- An `index-state` makes Hackage metadata selection repeatable. Update it in a
  reviewed dependency change; it does not pin package versions by itself.
- Put local development overrides in `cabal.project.local` and normally ignore
  that file. Do not require uncommitted local state for CI or release.
- Treat `source-repository-package` as executable source input: pin a commit,
  review provenance and build hooks, and replace temporary forks deliberately.
- Avoid global `allow-newer`, `allow-older`, or unconstrained `constraints` that
  conceal false package bounds. Narrow exceptions, document why, and expire them.

Inspect what Cabal solved rather than inferring it from declarations:

```bash
cabal build all --dry-run
cabal build all
```

For deeper review, inspect `dist-newstyle/cache/plan.json` directly or through
`cabal-plan`. Solver success proves that one plan exists, not that all declared
library bounds work.

## 4. Separate application reproducibility from library compatibility

Applications deploy one reviewed plan. Commit `cabal.project.freeze` when the
application needs reproducible builds, and update it through tested dependency
changes:

```bash
cabal update
cabal build all --dry-run
cabal freeze
cabal build all
cabal test all
```

A freeze file pins Haskell package versions and flags selected by Cabal. It does
not pin GHC, Cabal, the Hackage index unless `index-state` is set, system
libraries, C toolchains, operating system, or package source provenance.

Libraries publish ranges that describe consumer compatibility. Use meaningful
lower bounds backed by tests and upper bounds justified by known API risk. Do
not publish exact application pins as the library's dependency policy.

- Test a normal recent plan and a genuine lower-bound plan; inspect the latter's
  resolved versions. `--prefer-oldest` is a preference, not a proof.
- A checked-in freeze file may support library development or a CI job, but
  release checks must also solve from published ranges.
- When a lower bound fails, fix support or raise the bound. Do not keep the claim
  and patch CI with `allow-newer`.
- Keep `base` bounds, `tested-with`, documentation, and actual compiler jobs
  consistent. `tested-with` records evidence and does not constrain the solver.

## 5. Keep compiler and editor support claims truthful

Library CI should test the declared minimum compiler, a dynamically checked
current stable compiler, and any intermediate versions needed by the support
policy. Applications should test the deployed compiler and the intended upgrade
target. Print tool versions and preserve the resolved plan in CI logs.

Haskell Language Server must support the selected GHC version. Install a
compatible HLS through GHCup or use a repository-established method; if HLS
lags a newly released GHC, keep the project's supported compiler rather than
silently changing production compatibility for editor convenience.

```bash
ghcup list
ghcup install hls latest
haskell-language-server-wrapper --probe-tools
```

- HLS is a development tool, not an application dependency. Do not put it in a
  component's `build-depends`.
- Multi-component projects should expose accurate Cabal components and flags so
  HLS resolves the same modules as `cabal build`.
- Generated modules, CPP, plugins, and unusual preprocessors can make editor and
  build behavior diverge. Reproduce suspected diagnostics with Cabal before
  weakening compiler settings.

## 6. Format with Fourmolu and lint with HLint

For greenfield code, use Fourmolu as the deterministic formatter and HLint for
reviewable semantic suggestions. Pin tool versions in CI or a maintained tool
environment and keep configuration in the repository.

```bash
fourmolu --mode check app src test
hlint app src test
```

- Preserve an established Ormolu, Brittany, stylish-haskell, or other formatter
  if it is healthy. Do not create repository-wide formatting churn incidentally.
- Format only touched files unless a separately reviewed formatting migration is
  requested. Configure language extensions and fixity declarations so parsing
  matches the build.
- HLint output is advice, not a proof. Review changes for strictness, sharing,
  exception timing, readability, and asymptotic differences before applying.
- Keep ignored hints narrow and documented. Never auto-apply every hint across
  security-sensitive, concurrent, or performance-critical code.
- Scope `-Wall` and warning policy to local components. A designated strict job
  can use `-Werror`; avoid forcing warning flags onto dependencies.

## 7. Add dependencies deliberately

Before adding a package, check whether `base` or an existing dependency already
provides the needed operation. Then assess maintenance, license, API stability,
transitive graph, native code, flags, build-time execution, advisories, and
supported GHC range.

- Prefer a focused maintained package over copying complex protocol, crypto,
  Unicode, parser, or concurrency code.
- Avoid a large framework for one trivial helper. Dependency count is not the
  metric; maintenance and attack surface are.
- Review `Setup.hs`, Template Haskell, compiler plugins, preprocessors, and
  foreign sources because builds can execute them.
- Run `cabal outdated` as a planning aid, not an instruction to widen every
  bound. Test upgrades and review the changed plan.
- Check Haskell Security Response Team and ecosystem advisories on every change
  and on a schedule. A frozen plan can become vulnerable without changing.

## 8. Keep commands component-aware and release-ready

Use selectors to avoid accidentally testing only the default component:

```bash
cabal build all
cabal test all --test-show-details=direct
cabal bench all
cabal haddock all --haddock-all
cabal check
cabal sdist all
```

Run source-distribution checks from the generated tarball in a clean temporary
directory. This catches undeclared modules, fixtures, generated files, and
checkout-relative assumptions. Do not delete or reset an active worktree to
simulate cleanliness.

## References

- https://www.haskell.org/ghcup/
- https://www.haskell.org/ghcup/guide/
- https://www.haskell.org/ghcup/about/#security
- https://downloads.haskell.org/ghc/latest/docs/users_guide/
- https://cabal.readthedocs.io/en/stable/
- https://cabal.readthedocs.io/en/stable/cabal-project-description-file.html
- https://cabal.readthedocs.io/en/stable/cabal-package-description-file.html
- https://github.com/fourmolu/fourmolu
- https://github.com/ndmitchell/hlint
- https://haskell-language-server.readthedocs.io/
- https://github.com/haskell/security-advisories

## Audit checklist

```bash
# Toolchain and competing sources of truth
ghc --version
cabal --version
rg -n '(resolver:|stack|nix|ghcup|with-compiler|compiler:|hpack|package.yaml)' . --glob '*.{yaml,yml,nix,project,cabal}'

# Components, API surface, dependencies, warnings, and build-time execution
rg -n '^(library|internal-library|executable|test-suite|benchmark)|exposed-modules:|other-modules:|build-depends:|build-type:|custom-setup|build-tool-depends:' --glob '*.cabal'
rg -n '(TemplateHaskell|-fplugin|c-sources|cxx-sources|allow-newer|allow-older)' . --glob '*.{cabal,project,hs,lhs}'

# Solver reproducibility and application/library policy
rg -n '(index-state|constraints|source-repository-package|packages:)' --glob 'cabal.project*'
git ls-files | rg 'cabal\.project\.freeze$|\.cabal$|package\.yaml$'
cabal build all --dry-run
cabal outdated

# Formatter, linter, editor, and support claims
rg -n '(fourmolu|ormolu|brittany|stylish-haskell|hlint|haskell-language-server|tested-with|ghc-version)' . --glob '*.{cabal,project,yaml,yml,json,md}'
fourmolu --mode check app src test 2>/dev/null
hlint app src test 2>/dev/null
```

Command failures and grep hits are leads, not findings. Establish whether the
repository is an application or library, identify its declared support policy,
and preserve intentional existing tooling. Confirm the actual compiler, index,
solver plan, formatter configuration, and CI behavior before recommending a
migration or changing bounds.
