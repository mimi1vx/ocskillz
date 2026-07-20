---
name: sota-haskell
description: >-
  State-of-the-art Haskell engineering (2026) for writing and auditing Haskell
  code. Covers GHCup-managed GHC, Cabal projects and dependencies, type-driven
  API design, totality and evaluation, exceptions and resources, async/STM
  concurrency, security and FFI, profiling, Hspec/Tasty/QuickCheck, Haddock,
  Hackage packaging, and CI. Use for Haskell source, .cabal files,
  cabal.project, GHC extensions, libraries, services, tests, reviews,
  performance work, or security audits. Triggers: Haskell, GHC, GHCup, Cabal,
  .hs, .lhs, .cabal, HLS, Fourmolu, HLint, QuickCheck, STM, async, FFI, Hackage.
license: MIT
metadata:
  source: local synthesis from GHC, Cabal, GHCup, Hackage, and ecosystem documentation
  maintained-for: opencode
---

# SOTA Haskell (2026)

## Local integration policy

Read `AGENTS.md`, `.cabal` files, `cabal.project*`, CI, formatter/linter config,
and the declared compiler range before changing code. For greenfield work,
prefer **GHCup** for GHC, Cabal, and HLS installation; **Cabal** for builds,
dependency solving, tests, benchmarks, and packaging; **Fourmolu** for
formatting; and **HLint** for reviewed suggestions. Do not introduce Stack or
Nix as the default package/build interface. Preserve an effective established
Stack, Nix, Ormolu, stylish-haskell, test framework, or CI workflow unless the
user requests migration. A different working toolchain is not an audit finding.

Determine the latest stable compiler from current official GHC/GHCup metadata
at the time of the task. Do not infer it from this file or silently install or
switch compilers. As verified in July 2026, GHC 9.14.1 is latest stable; this is
a dated example, not a permanent pin. For an existing repository, honor its
declared GHC and `base` compatibility. Confirm HLS and dependency support before
adopting a newly released GHC.

This skill owns Haskell semantics, compiler/package mechanics, and runner
syntax. `sota-testing` owns language-neutral test strategy and suite health;
`sota-code-security` owns cross-language trust-boundary architecture;
`sota-sandboxing` owns isolation for hostile compilation/execution; and
`deep-performance-audit` owns baseline/profile/equivalence methodology.

## Purpose

This skill serves two modes:

- **BUILD**: write or modify production Haskell to this standard.
- **AUDIT**: inspect Haskell code and report prioritized, evidenced findings.

Read this file fully, then load only the relevant files under `rules/`. Every
rule file ends with an audit checklist. Commands and searches produce leads;
read surrounding code and establish evaluation, ownership, compatibility, and
data flow before reporting a defect.

## BUILD mode

1. **Establish the compatibility contract.** Inspect GHC and `base` bounds,
   `tested-with`, project files, freeze files, CI matrices, flags, and installed
   `ghc --version`/`cabal --version`. New projects use a currently verified
   stable GHC through GHCup; libraries support only versions they actually test.
2. **Model the domain with types and modules.** Prefer ADTs and validated
   newtypes, explicit export lists, small capability-oriented classes, and
   constructors that make invalid states difficult to represent. Keep public
   APIs minimal and document strictness, exceptions, effects, and complexity.
3. **Keep failure and evaluation explicit.** Use total functions at public and
   hostile-input boundaries, typed expected errors, narrow exception handling,
   bracketed resources, strictness only where ownership or measurements require
   it, and explicit streaming instead of lazy I/O for scarce resources.
4. **Own concurrency.** Scope child threads with `withAsync`/structured
   combinators, preserve async-exception semantics, keep STM invariants in one
   transaction, bound queues and fan-out, and define graceful shutdown.
5. **Treat unsafe and build-time code as trust boundaries.** Contain
   `unsafePerformIO`, `unsafeCoerce`, FFI, Template Haskell, plugins, custom
   setup, parsers, paths, and subprocesses. Safe Haskell is not a sandbox.
6. **Test behavior.** Use the established Hspec/Tasty/HUnit suite, QuickCheck
   for laws and state machines, deterministic regression tests for shrunk
   failures, and clean source-distribution tests for released libraries. Load
   `sota-testing` for non-trivial test design.
7. **Measure performance.** Start with optimized representative baselines and
   `+RTS -s`; use eventlogs, cost-centre/heap profiles, and Criterion as the
   hypothesis requires. Verify equivalent forcing and outputs before claiming
   improvement.
8. **Verify with project gates.** Use repository commands first. Greenfield
   baseline: Fourmolu check, HLint, `cabal check`, `cabal build all`, `cabal
   test all`, and `cabal haddock all`; run benchmarks, coverage, source-tarball,
   lower-bound, FFI sanitizer, or compiler-matrix gates when scope warrants.

## AUDIT mode

1. **Recon first.** Inventory `.hs`/`.lhs`/`.hsc`/`.chs` and `.cabal` files,
   project/freeze files, GHC/Cabal versions, components, dependency plan,
   extensions, CI, unsafe/FFI/TH code, test suites, and runtime options.
2. **Run configured gates before supplemental tools.** Existing build, test,
   format, lint, docs, and packaging commands are authoritative. Do not impose a
   greenfield Fourmolu or HLint policy on an unrelated legacy review.
3. **Apply relevant audit checklists.** Treat `rg`, HLint, compiler warnings,
   dependency reports, profiles, and coverage as heat maps. A partial function,
   raw `forkIO`, lazy value, orphan instance, or `unsafe` call may be justified
   by a local invariant; verify it.
4. **Trace non-local semantics.** Confirm what is forced and when, who owns each
   resource/thread, which exceptions can arrive, whether queues and input are
   bounded, and whether public compatibility claims match CI.
5. **Separate defects from preferences.** Report crashes, leaks, deadlocks,
   data loss, injection, unsound abstraction, false bounds, and measured
   regressions. Do not inflate alternate formatters, test frameworks, effect
   styles, Stack/Nix use, or extension choices into defects by themselves.
6. **Report evidence and confidence.** Quote the relevant line, explain the
   concrete failure path, and distinguish confirmed behavior from a suspected
   lead requiring runtime, compiler, or dependency evidence.

### Severity conventions

| Severity | Meaning | Examples |
|---|---|---|
| CRITICAL | Direct compromise, arbitrary code, memory unsafety, or destructive corruption | shell injection; attacker-controlled build/plugin execution with secrets; proven `unsafeCoerce`/FFI type or lifetime violation; auth bypass |
| HIGH | Realistic exploit or production-breaking correctness failure | unbounded hostile input/queue causing OOM; async-exception resource leak or deadlock; swallowed cancellation; path traversal/TOCTOU; public partiality reachable from untrusted data; false compatibility causing release failure |
| MEDIUM | Latent defect or materially weakened defense | orphaned child; lazy state space leak; inaccurate dependency lower bound; unchecked process exit; unreviewed TH/custom setup; missing clean-sdist test for a release |
| LOW | Maintainability, portability, or hygiene risk | broad exports; undocumented partial invariant; stale extension; unscoped HLint suppression; missing Haddock contract |
| INFO | Useful observation without required action | optional tooling consolidation; future compiler support opportunity |

Severity scales with reachability, attacker control, data/resource loss, and
blast radius. Confidence is **confirmed** when the relevant data, evaluation,
ownership, or build path was traced and **suspected** when more evidence is
required.

### Finding format

```text
[SEVERITY/confidence] short title
  Where: src/Example.hs:42 (module/function/component)
  Issue: defect and relevant data, evaluation, or ownership flow
  Impact: concrete exploit, crash, leak, deadlock, compatibility, or operational cost
  Evidence: offending code plus observed compiler/runtime/profile behavior
  Fix: smallest specific correction; cite rules/NN section
  Effort: trivial | small | medium | large
```

Group findings by severity. End with commands run, rule files applied,
explicitly clean areas, and anything not reviewed.

## Rules index

| File | Read this when... |
|---|---|
| [rules/01-tooling-project-dependencies.md](rules/01-tooling-project-dependencies.md) | Selecting GHC/GHCup/Cabal/HLS; scaffolding packages or workspaces; editing `.cabal`, `cabal.project`, freeze files, bounds, formatter/linter config, or dependency plans |
| [rules/02-types-api-design.md](rules/02-types-api-design.md) | Designing ADTs, newtypes, classes, instances, modules, export lists, deriving, roles, extensions, public compatibility, or Haddock APIs |
| [rules/03-evaluation-errors-resources.md](rules/03-evaluation-errors-resources.md) | Reasoning about laziness, strictness, bottom, partial functions, typed errors, exceptions, async exceptions, resource cleanup, streaming, Text, or ByteString |
| [rules/04-concurrency-parallelism.md](rules/04-concurrency-parallelism.md) | Using async/forkIO, STM, MVar, queues, cancellation, masking, parallel strategies, capabilities, worker pools, or graceful shutdown |
| [rules/05-security-ffi-supply-chain.md](rules/05-security-ffi-supply-chain.md) | Handling hostile input, paths, commands, archives, secrets, unsafe functions, Template Haskell/plugins/custom Setup, Safe Haskell, FFI, native lifetimes, or dependency advisories |
| [rules/06-performance.md](rules/06-performance.md) | Investigating CPU, allocation, residency, GC, laziness, data structures, fusion, concurrency scaling, Criterion benchmarks, Core, or performance claims |
| [rules/07-testing-ci-packaging.md](rules/07-testing-ci-packaging.md) | Writing/running Cabal tests, Hspec/Tasty/HUnit, QuickCheck, golden tests, HPC, doctest/Haddock, compiler matrices, lower bounds, source distributions, Hackage releases, or provenance |

## Top-10 non-negotiables

1. **GHCup manages the greenfield toolchain; Cabal is the build/package
   interface.** Verify latest stable dynamically and confirm ecosystem support;
   preserve established project tooling unless migration is requested. (rules/01)
2. **Compatibility claims are tested contracts.** GHC/`base` bounds,
   `tested-with`, docs, dependency bounds, and CI must agree; applications use a
   reviewed resolved plan while libraries test published ranges. (rules/01, 07)
3. **Make invalid states difficult to represent.** Use ADTs/newtypes, private
   constructors, smart constructors, explicit exports, and lawful instances;
   avoid orphan/overlapping instances without a documented coherence plan.
   (rules/02)
4. **No unproven partiality at public or hostile-input boundaries.** Replace
   `head`, `read`, `fromJust`, `!!`, incomplete matches, and `error` with total
   parsing or typed failure unless a local invariant is established and tested.
   (rules/02, 03)
5. **Every scarce resource has lexical ownership.** Use `bracket`, `withFile`,
   or equivalent; avoid lazy I/O where handle lifetime escapes; cleanup remains
   correct under synchronous and asynchronous exceptions. (rules/03)
6. **Every concurrent action has an owner and bound.** Scope async work, observe
   failures, bound queues/fan-out, keep STM invariants atomic, and make shutdown
   finite and testable. (rules/04)
7. **Unsafe, FFI, and build-time execution are isolated and reviewed.** Keep
   tiny safe wrappers around unsafe primitives, prove native lifetimes/ABI, and
   sandbox untrusted builds; Safe Haskell alone is not isolation. (rules/05)
8. **Untrusted data is bounded before expensive work.** Cap bytes, nesting,
   counts, decompression, allocation, process output, and parser time; commands
   use executable plus argv and paths use capability-safe operations. (rules/05)
9. **No optimization without forcing-correct evidence.** Baseline optimized
   representative work, profile the relevant resource, validate equivalent
   output/evaluation, and benchmark before/after; strictness and `INLINE` are
   not reflexes. (rules/06)
10. **Release artifacts are tested, not inferred from checkout success.** Gate
    format/lint/build/test/docs as configured, exercise relevant compiler and
    dependency ranges, and build/test the exact clean source distribution that
    will be published. (rules/07)

## Primary references

- https://downloads.haskell.org/ghc/latest/docs/users_guide/
- https://www.haskell.org/ghcup/
- https://cabal.readthedocs.io/en/stable/
- https://hackage.haskell.org/
- https://github.com/haskell/security-advisories
- https://fourmolu.github.io/
- https://github.com/ndmitchell/hlint
- https://haskell-language-server.readthedocs.io/
