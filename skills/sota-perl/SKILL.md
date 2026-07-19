---
name: sota-perl
description: >-
  State-of-the-art Perl 5 engineering (2026) for writing and auditing Perl
  code. Covers supported Perl selection, cpanfile and CPAN dependencies,
  Perl semantics and Unicode, modules and Moo APIs, errors, processes and
  async I/O, perlsec and supply-chain hardening, NYTProf performance work,
  Test2/prove, packaging, and CI. Use for Perl source, CPAN distributions,
  cpanfile, Makefile.PL, dist.ini, Minilla, DBI, Mojolicious, IO::Async, XS,
  tests, reviews, debugging, modernization, or security audits. Triggers:
  Perl, .pl, .pm, .t, CPAN, PAUSE, cpanm, cpm, Carton, Perl::Critic,
  perltidy, prove, Test2, Moo, DBI, Devel::NYTProf.
license: MIT
metadata:
  source: local synthesis from Perl and CPAN documentation
  maintained-for: opencode
---

# SOTA Perl 5 (2026)

## Local integration policy

Read `AGENTS.md`, `cpanfile`, distribution metadata, lock/snapshot files, CI,
and the declared minimum Perl before changing code. For a new project, use a
currently supported stable Perl, `cpanfile`, current `cpm`, perltidy, a
curated Perl::Critic profile, and Test2/prove. Preserve an established
project's Perl floor, installer, authoring system, style, and test framework
unless migration is requested. A working Carton, Carmel, cpanm, Dist::Zilla,
Minilla, Test::More, Moo/Moose, or framework-specific workflow is not a
finding merely because another tool is newer.

Verify current releases and support status from `perlpolicy`, perl.org, and
MetaCPAN instead of relying on version numbers embedded here. As of July
2026, Perl 5.44 is current stable, 5.42 is previous stable, and 5.40 receives
security fixes; that state will change.

This skill owns Perl semantics and runner/tool syntax. `sota-testing` owns
language-neutral test strategy, `sota-code-security` owns cross-language
security architecture, and `deep-performance-audit` owns performance
baselining and equivalence proof.

## Purpose

This skill serves two modes:

- **BUILD**: write or modify production Perl to this standard.
- **AUDIT**: inspect Perl code and report prioritized, evidenced findings.

Read this file fully, then load only the relevant files under `rules/`.
Every rule file ends with an audit checklist. Commands in those checklists
produce leads; read the code and trace data flow before reporting findings.

## BUILD mode

1. **Establish the compatibility contract.** Inspect `use VERSION`, metadata,
   CI matrices, `.perl-version`, and `perl -V`. Use only syntax supported by
   the declared floor. New applications target a supported stable Perl;
   libraries choose and test the oldest version their users actually need.
2. **Keep dependency intent explicit.** Declare dependencies in `cpanfile` or
   the repository's canonical metadata. Applications commit their existing
   snapshot/lock and install in a clean environment; libraries publish
   version ranges rather than forcing a consumer lock.
3. **Write readable, lexical Perl.** Use a stable version bundle, lexical
   variables, signatures where the floor permits, explicit context, lexical
   filehandles, three-argument `open`, strict Unicode boundaries, and
   documented return/error contracts.
4. **Keep risky behavior explicit.** No shell-string execution, interpolated
   SQL, string `eval`, unsafe deserialization, symbolic references, or
   unchecked path use on untrusted input. Taint mode is defense in depth,
   never a sandbox.
5. **Own process and async lifetimes.** Reap every child, close inherited pipe
   ends, bound queues and concurrency, set deadlines, propagate cancellation,
   and use the event loop already selected by the application.
6. **Test behavior.** Use the project's existing Test2/Test::More stack and
   `prove`; add focused tests for error paths, context-sensitive APIs,
   malformed bytes, and trust boundaries. Load `sota-testing` when writing
   non-trivial logic.
7. **Verify with project gates.** At minimum, syntax-check changed Perl,
   format/lint with the configured profiles, run relevant tests, and audit
   dependencies when manifests changed. New-project defaults are `perl -c`,
   `perltidy --assert-tidy`, `perlcritic`, `prove -lr t`, and `cpan-audit`.

## AUDIT mode

1. **Recon first.** Inventory Perl versions, `.pl`/`.pm`/`.t` and XS files,
   dependency declarations/snapshots, build system, CI, frameworks, DBI,
   subprocesses, deserializers, and event loops. Run `perl -V` when the active
   interpreter matters.
2. **Run configured gates before supplemental tools.** Existing test, tidy,
   critic, author-test, and dependency-audit commands are authoritative. Do
   not silently impose a new profile on a legacy repository.
3. **Apply relevant checklists.** Treat grep and Perl::Critic output as a heat
   map. Validate reachability, input control, mitigations, platform behavior,
   and the declared Perl floor.
4. **Separate defects from preferences.** Report injection, data loss,
   context bugs, unreaped children, broken cancellation, and unsupported
   syntax. Do not inflate alternate formatting, OO, installer, or authoring
   choices into defects.
5. **Report evidence and confidence.** Quote the relevant line, explain the
   concrete failure mode, and distinguish confirmed data flow from a pattern
   that still needs tracing.

### Severity conventions

| Severity | Meaning | Examples |
|---|---|---|
| CRITICAL | Direct compromise, arbitrary code, or destructive corruption | untrusted string `eval`, executable object deserialization, SQL injection, shell injection in a privileged process |
| HIGH | Realistic exploit or production-breaking correctness failure | two-argument `open` on user input, traversal/TOCTOU, leaked secrets, unreaped process storm, unbounded hostile-input regex, unsupported syntax on the declared floor |
| MEDIUM | Latent defect or materially weakened defense | ambiguous context contract, swallowed `$@`, partial async operation reused after timeout, unlocked application deploy, no dependency audit, encoding-boundary loss |
| LOW | Maintainability, portability, or hygiene risk | broad exports, package globals, unscoped critic suppression, undocumented experimental feature, missing author check |
| INFO | Useful observation without required action | optional tool consolidation, future floor-bump opportunity |

Severity scales with attacker control, privilege, reachability, and blast
radius. Confidence is **confirmed** when the flow was traced and **suspected**
when more evidence is required.

### Finding format

```text
[SEVERITY/confidence] short title
  Where: path/to/file.pm:42 (package/subroutine)
  Issue: defect and relevant data or control flow
  Impact: concrete exploit, failure, compatibility, or operational cost
  Evidence: offending code and any observed behavior
  Fix: smallest specific correction; cite rules/NN section
  Effort: trivial | small | medium | large
```

Group findings by severity. End with commands run, rule files applied,
explicitly clean areas, and anything not reviewed.

## Rules index

| File | Read this when... |
|---|---|
| [rules/01-tooling-project-dependencies.md](rules/01-tooling-project-dependencies.md) | Selecting Perl/tooling; editing cpanfile, snapshots, Makefile.PL, dist.ini, minil.toml, perltidy/critic config, dependency installs, or project layout |
| [rules/02-semantics-idioms.md](rules/02-semantics-idioms.md) | Writing general Perl; handling context, truthiness, references, signatures, regexes, Unicode, filehandles, scoping, or language-version compatibility |
| [rules/03-modules-apis-oo-errors.md](rules/03-modules-apis-oo-errors.md) | Designing modules, exports, public APIs, Moo/Moose or blessed objects, exceptions, cleanup, logging, and compatibility |
| [rules/04-concurrency-async-processes.md](rules/04-concurrency-async-processes.md) | Forking, subprocess supervision, IPC, signals, threads, IO::Async/Future, Mojo promises, timeouts, cancellation, or graceful shutdown |
| [rules/05-security-supply-chain.md](rules/05-security-supply-chain.md) | Handling untrusted input, files, SQL, commands, regexes, Unicode identifiers, deserialization, secrets, CPAN installs, or security audits |
| [rules/06-performance.md](rules/06-performance.md) | Investigating speed, memory, startup, regex, DBI, serialization, allocation, XS, benchmarks, or performance claims |
| [rules/07-testing-ci-packaging.md](rules/07-testing-ci-packaging.md) | Writing/running tests, coverage, property/fuzz checks, CI matrices, CPAN metadata, author/release tests, tarballs, PAUSE releases, or provenance |

## Top-10 non-negotiables

1. **Use a declared stable version bundle and test the declared minimum.** New
   code uses `use v5.36` or newer when compatibility permits; never enable
   `:all` or experimental features accidentally. (rules/01, 02)
2. **No shell strings from variable data.** Use list-form `system`/`exec` or
   multi-argument pipe `open`, absolute executables where trust matters, `--`
   before user operands, deadlines, and checked exit status. (rules/05)
3. **Lexical handles and three-argument `open` only.** Set `:encoding(UTF-8)`
   or `:raw` deliberately; check `open`, `close`, writes, and pipe status.
   (rules/02, 05)
4. **SQL values are always bound.** Identifiers come from an authorization-
   checked allowlist; transactions have explicit rollback behavior. (rules/05)
5. **Never deserialize hostile Perl objects or execute hostile text.** No
   string `eval`, `s///ee`, Storable thaw/retrieve, or YAML Perl/object tags
   across a trust boundary. (rules/05)
6. **Decode bytes strictly at input and encode at output.** `use utf8` affects
   source, not I/O; malformed input, normalization, ASCII-only protocols, and
   grapheme semantics are explicit decisions. (rules/02, 05)
7. **Every child and async operation has an owner.** Reap children, close
   unused descriptors, bound fan-out, set deadlines, and define cancellation
   and partial-I/O behavior. Do not mix event loops casually. (rules/04)
8. **Context is part of the API.** Avoid surprising scalar/list differences;
   distinguish false from undefined; use references for structured arguments
   and returns. (rules/02, 03)
9. **Applications deploy from a committed snapshot in a clean, matching
   environment; CPAN libraries publish tested ranges.** Update CPAN::Audit,
   check database age, and audit the interpreter and dependencies. (rules/01, 05)
10. **No optimization without evidence.** Profile representative work with
    NYTProf and separately observe DB/network latency; benchmark equivalent
    implementations and protect behavior with tests. (rules/06)

## Primary references

- https://perldoc.perl.org/perlpolicy
- https://perldoc.perl.org/perlstyle
- https://perldoc.perl.org/perlsec
- https://perldoc.perl.org/feature
- https://security.metacpan.org/
- https://metacpan.org/
