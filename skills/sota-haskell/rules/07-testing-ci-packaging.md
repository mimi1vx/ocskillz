# 07 - Testing, CI, Packaging, and Release

This file owns Haskell framework, Cabal, compiler-matrix, documentation, and
release mechanics. Load `sota-testing` for suite shape, doubles, fixtures,
determinism, property design, coverage policy, and flake handling.

## 1. Cabal test-suite mechanics

Declare each suite explicitly in the `.cabal` file:

```cabal
test-suite unit
  type:             exitcode-stdio-1.0
  main-is:          Spec.hs
  hs-source-dirs:   test
  build-depends:
      base
    , example
    , hspec
  default-language: GHC2024
```

- Prefer `exitcode-stdio-1.0`: the executable returns zero on success and
  nonzero on failure, and works with any framework. Preserve an established
  `detailed-0.9` suite rather than rewriting it without a concrete reason.
- Put test-only dependencies in the suite's `build-depends`; do not expose them
  from the library. Declare test data through `data-files` or
  `extra-source-files` as appropriate so it reaches the source distribution.
- A suite can depend on the package's public library by package name. An
  internal library is useful for testing application internals without making
  them public, but do not create one solely to evade a sound API boundary.
- Use `build-tool-depends` for executable test tools, not an undeclared binary
  assumed to be on `PATH`.
- `cabal test all` builds and runs enabled suites. Use
  `--test-show-details=direct` locally and `--test-show-details=streaming` or
  an established CI reporter when useful; always retain complete failure logs.

Common commands:

```bash
cabal update
cabal build all
cabal test all --test-show-details=direct
cabal test unit --test-options='--match parser'
```

Test options after `--test-options` belong to the selected test executable and
are framework-specific. Do not assume an Hspec option works in Tasty or HUnit.

## 2. Framework choice

- Preserve Hspec, Tasty, or HUnit in a healthy existing suite. Framework churn
  rarely improves behavior coverage and can erase useful integrations.
- For greenfield behavior-oriented unit and integration suites, Hspec is a good
  concise default with readable nested specs and strong QuickCheck support.
- Choose Tasty when one tree must compose HUnit, QuickCheck, golden, benchmark,
  or other providers and needs consistent filtering, ingredients, or reporting.
- HUnit remains suitable for small suites and as a Tasty provider. Its lower
  abstraction level is not a reason to migrate working tests.
- Avoid framework dogma: choose from team familiarity, provider needs, output,
  and maintenance status. Assert public behavior rather than constructor or
  call choreography unless that detail is the contract.

## 3. QuickCheck

Use QuickCheck where the domain has laws: round trips, parser/printer agreement,
normalization idempotence, algebraic laws, model equivalence, and state-machine
invariants. Keep focused examples for named regressions and boundary behavior.

```haskell
prop_roundTrip :: Value -> Property
prop_roundTrip value =
  classify (isEmpty value) "empty" $
  cover 10 (isNested value) "nested" $
  decode (encode value) === Right value
```

- Define `Arbitrary` only when one canonical, broadly useful distribution and
  shrinker exist. Otherwise use explicit generators or wrapper `newtype`s so a
  property's domain is visible.
- Prefer constructive generators over heavy `suchThat`; discarded cases waste
  the test budget and can hide an unreachable domain.
- Supply semantic shrinking when generic shrinking violates invariants or
  obscures the defect. A shrinker must produce smaller valid candidates and
  terminate; test important custom generators and shrinkers themselves.
- Use `classify`, `collect`, `tabulate`, and `cover`/`checkCoverage` to prove the
  generator reaches meaningful categories. Passing 100 nearly identical easy
  cases is weak evidence.
- Preserve the replay seed and size printed on failure. Add the minimal shrunk
  counterexample as a deterministic regression test rather than trusting a
  future random run to rediscover it.
- Keep PR case counts bounded; move large runs to an owned scheduled job.
  Increasing `maxSuccess` does not repair a poor generator.

## 4. Determinism and isolation

- Tests must not depend on execution order, hash/map ordering, current working
  directory, ambient environment, locale, timezone, network, or wall clock
  unless that behavior is under test.
- Use per-test temporary directories and unique resources. Resolve packaged
  data through Cabal-generated paths rather than repository-relative paths.
- Inject clocks and RNGs. For generated failures, print enough replay data to
  reproduce exactly; do not merely rerun until green.
- Avoid fixed ports and sleeps. Ask the OS for an ephemeral port and signal
  readiness through synchronization or polling with a bounded deadline.
- Hspec and Tasty may execute tests concurrently depending on configuration and
  options. Make isolation explicit; serialize only the resource-bound group,
  not the whole suite.
- Pin locale/timezone in CI only when that is the intended contract; also test
  relevant alternate settings when the package claims portability.

## 5. Golden tests

Golden tests are appropriate for stable, reviewable renderings such as pretty
printers, generated code, diagnostics, and serialization fixtures.

- Store golden inputs and expected outputs in the source distribution and read
  them without assuming the checkout root.
- Normalize only irrelevant nondeterminism such as platform line endings or a
  deliberately unstable path. Do not normalize away meaningful ordering,
  timestamps, or identifiers merely to make a failure pass.
- A golden update is a reviewed behavior change, not an automatic CI repair.
  CI must never overwrite and accept expected files.
- Prefer semantic assertions for structured formats when textual formatting is
  not the contract. Keep golden files small enough for a reviewer to understand.
- `tasty-golden` and Hspec-compatible helpers are both reasonable; preserve the
  suite's framework rather than introducing a second runner for this feature.

## 6. HPC coverage semantics

```bash
cabal test all --enable-coverage
```

Cabal compiles local components with HPC and writes per-suite reports under
`dist-newstyle`. Exact paths are Cabal-version and component dependent; consume
the generated report or discover `.tix` files instead of hard-coding a fragile
store path. For direct HPC work, use `hpc report`, `hpc markup`, and deliberate
`.tix`/mix-directory selection.

- HPC counts expression tick boxes, alternatives, and boolean outcomes; it is
  not equivalent to source-line coverage and does not prove assertions.
- Optimizations, inlining, CPP, generated code, Template Haskell, and modules
  compiled outside the instrumented plan can change or omit ticks. Compare
  results only under a stable compiler/build configuration.
- Multiple suites produce separate `.tix` data unless intentionally combined.
  Combining incompatible or duplicate module hashes is invalid; verify the
  resulting module set rather than trusting a merged percentage.
- Use coverage to locate unexercised behavior, especially alternatives and
  error paths. Do not impose an arbitrary global percentage or weaken code and
  tests to satisfy one; follow `sota-testing` for ratchets and audit policy.

## 7. Doctest and Haddock

Doctest examples are executable documentation, not a replacement for normal
tests. `doctest` recompiles/interprets modules in its own context, so Cabal
flags, CPP, generated modules, plugins, package visibility, working directory,
and component-specific options can diverge from the real build.

- Prefer a maintained Cabal-aware integration already used by the repository.
  If invoking `doctest` directly, pass the same source dirs, extensions, CPP
  options, and package environment deliberately and test it in CI.
- Keep examples deterministic and small. Avoid examples requiring network,
  locale, mutable external state, or unstable `Show` output.
- Do not place a fragile doctest invocation in consumer-facing test suites when
  it requires undeclared checkout state. It may be an author check instead.
- Run Haddock with warnings visible and include internal/public components as
  intended:

```bash
cabal haddock all --haddock-all --haddock-hyperlink-source
```

Treat broken links, malformed markup, and missing documentation according to the
project's public-API policy. Haddock success does not execute examples unless a
separate doctest integration does so.

## 8. Compiler matrix and warning policy

Library CI should test the declared minimum GHC and a dynamically verified
current/latest stable GHC, plus intermediate versions needed to support the
package's stated range. Applications should test the deployed compiler and
planned upgrade target. Resolve "latest stable" from current GHCup/Haskell
release metadata when maintaining CI; do not let a once-current literal become
an accidental support claim.

GHC 9.14.1 is a dated July 2026 example only, not a permanent recommendation.
The package's `base` bounds, `tested-with`, documentation, and actual CI must
tell a consistent story. `tested-with` records evidence; it does not constrain
dependency solving or replace a matrix run.

- For greenfield CI, prefer GHCup to install GHC and Cabal, then use Cabal as
  the build/test interface. Preserve established Stack or Nix CI when it
  reproducibly tests the claimed matrix; do not migrate tooling for fashion.
- Print `ghc --version`, `cabal --version`, and the resolved plan in every job.
- Make normal warnings visible and fix project warnings. `-Werror` is often
  useful for application code or a designated newest-GHC job.
- For libraries, blanket `-Werror` across every compiler can turn new warnings
  in a newer GHC into failures unrelated to consumer correctness. Prefer
  `-Wall` plus a strict designated job, or narrowly exempt understood warning
  drift. Never suppress all warnings to keep old compilers green.
- Do not force warning flags onto dependencies. Scope them to local components.
- Keep a non-blocking future/nightly compiler job only if failures have an
  owner; unreleased compilers are early-warning signals, not support promises.

## 9. Lower bounds and dependency plans

Library version ranges are executable compatibility claims. A normal solver
usually selects recent dependencies and therefore does not prove lower bounds.

- Test the declared minimum GHC with a compatible plan and run a dedicated
  lower-bound solve/build using Cabal's supported solver options or an
  established repository tool such as `cabal-plan`-based bounds workflows.
- Inspect `cabal build --dry-run` output and `cabal-plan`'s `plan.json` view to
  verify what was actually selected. A job named "lower bounds" that resolves
  latest versions proves nothing.
- `--prefer-oldest` is a solver preference, not proof that every independent
  lower-bound combination is valid. Confirm the plan and account for coupled
  constraints, boot packages, flags, and setup dependencies.
- When a lower-bound failure reveals an inaccurate range, either support that
  version and fix the code or raise the bound. Do not add `allow-newer` and
  continue claiming an untested range.
- Preserve established tools such as `cabal-plan`, `cabal-plan-bounds`, or
  `cabal-install` workflows when maintained and inspectable; tool output is
  evidence only when CI builds and tests the resulting plan.

## 10. Source distributions and release checks

Run the complete release path, not only a checkout build:

```bash
cabal check
cabal build all
cabal test all
cabal haddock all --haddock-all
cabal sdist all
```

Then unpack the generated source tarball into a clean directory, without the
checkout's `dist-newstyle`, untracked files, package environment, or implicit
tools, and run at least `cabal build all`, `cabal test all`, and `cabal haddock
all`. This catches missing modules, fixtures, license files, generated sources,
and accidental repository-relative paths.

- Review `cabal check`; do not blindly waive warnings that affect Hackage
  metadata, portability, or installability.
- Verify the tarball contains the intended license, changelog, documentation,
  test data, and generated artifacts, and excludes secrets and build outputs.
- Build once from a reviewed protected tag, test that exact artifact, record a
  SHA-256 digest, and upload the identical bytes. Do not rebuild separately
  after CI succeeds.
- Keep Hackage credentials out of pull-request jobs and use a protected release
  environment. Pin third-party CI actions to reviewed commit SHAs where the
  threat model warrants it.

## 11. Hackage releases, revisions, and provenance

- Upload and inspect a Hackage candidate before publishing. Confirm rendered
  Haddocks, metadata, module exposure, dependencies, and installability from
  the candidate artifact.
- A Hackage revision changes only permitted package metadata, commonly bounds;
  it does not replace source tarball bytes. Use revisions narrowly to repair
  metadata compatibility, document them, and retain the source release tag.
- Never revise bounds to claim compatibility without build/test evidence. If
  source must change, publish a new package version rather than treating a
  revision as a patch channel.
- Preserve immutable tags, release notes, artifact digest, compiler/tool
  versions, and CI provenance. Signing or an attestation can establish origin
  and build linkage but does not prove correctness, and clients may not verify
  it automatically.
- Smoke-test the published artifact through the normal Hackage index path. Do
  not overwrite or silently replace a released version.

## 12. Freeze files and library ranges

Applications should use `cabal.project.freeze` or an equivalent committed lock
mechanism when reproducible deploys require a reviewed dependency plan. Update
it deliberately, test upgrades, and keep the compiler/toolchain pinned by the
deployment environment as well; a freeze file alone does not pin GHC or system
libraries.

Libraries should publish truthful lower and upper dependency ranges and test
them. Do not use a checked-in freeze file as evidence that consumers can solve
the package, and do not ship application-style exact constraints as library
compatibility policy. A repository may retain a freeze file for a specific CI
or development workflow, but release validation must also solve from the
published ranges.

## Audit checklist

```bash
# Cabal suites, dependencies, fixtures, and framework inventory
rg -n '^test-suite|type:|main-is:|hs-source-dirs:|build-depends:|build-tool-depends:|data-files:|extra-source-files:' --glob '*.cabal'
rg -n 'Hspec|Test\.Tasty|Test\.HUnit|QuickCheck|tasty-golden|doctest' --glob '*.{hs,cabal,project,yaml,yml,nix}'

# Property quality, shrinking, classification, and suspicious nondeterminism
rg -n 'property|forAll|Arbitrary|arbitrary|shrink|suchThat|classify|collect|tabulate|cover|checkCoverage|replay' --glob '*.hs'
rg -n '\b(threadDelay|randomIO|getCurrentTime|setEnv|withArgs)\b|localhost:[0-9]+|/tmp/' test spec --glob '*.hs' 2>/dev/null

# Coverage, docs, warning policy, and disabled tests
rg -n 'enable-coverage|hpc (report|markup)|doctest|cabal haddock|-Werror|-Wwarn|-Wall|pending|xit|ignore|retry|flaky' .github .gitlab-ci.yml --glob '*.{cabal,project,yaml,yml,hs,nix}' 2>/dev/null

# Compiler/tool matrix and actual support claims
rg -n 'ghc-version|compiler:|ghcup|setup-haskell|stack|nix|tested-with|base[[:space:]]*[<>=^]' .github .gitlab-ci.yml --glob '*.{cabal,project,yaml,yml,nix}' 2>/dev/null
ghc --version
cabal --version
cabal build all --dry-run

# Bounds, freeze files, release path, and artifact/provenance controls
rg -n 'prefer-oldest|cabal-plan|allow-newer|cabal\.project\.freeze|cabal (check|sdist|upload)|hackage|attest|provenance|id-token|pull_request_target' .github .gitlab-ci.yml --glob '*.{cabal,project,yaml,yml,nix}' 2>/dev/null
git ls-files | rg '(^|/)(dist-newstyle|\.stack-work|result)(/|$)|\.tar\.gz$|\.tix$'
```

Read command hits in context. Confirm support claims before reporting a missing
compiler or platform; an internal application does not need a public-library
release matrix. `-Werror`, freeze files, Stack/Nix, doctest, golden tests, and
coverage thresholds are not findings by themselves: evaluate their scope,
purpose, maintenance, and observed failure mode. Audit clean-tarball behavior in
a disposable directory rather than deleting an active worktree's build state.

## References

- https://cabal.readthedocs.io/en/stable/cabal-package-description-file.html#test-suites
- https://cabal.readthedocs.io/en/stable/how-to-package-haskell-code.html
- https://cabal.readthedocs.io/en/stable/cabal-commands.html
- https://cabal.readthedocs.io/en/stable/nix-local-build.html
- https://downloads.haskell.org/ghc/latest/docs/users_guide/profiling.html#haskell-program-coverage
- https://hackage.haskell.org/package/QuickCheck/docs/Test-QuickCheck.html
- https://hspec.github.io/
- https://github.com/UnkindPartition/tasty
- https://hackage.haskell.org/package/HUnit
- https://haskell-haddock.readthedocs.io/
- https://github.com/sol/doctest
- https://github.com/haskell/cabal-plan
- https://hackage.haskell.org/upload
- https://github.com/haskell-infra/hackage-trustees/blob/master/revisions-information.md
- https://www.haskell.org/ghcup/
