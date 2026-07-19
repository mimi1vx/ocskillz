# 07 - Testing, CI, Packaging, and Release

This file owns Perl runner, distribution, and CI mechanics. Load `sota-testing`
for suite shape, doubles, fixtures, determinism, property design, and flake
policy.

## 1. Test runner and framework

Run TAP tests with prove:

```bash
prove -lr t
prove -lrv t
prove -lr --shuffle t
prove -lr -j4 t
```

- Test2::V0 is the default for new suites; it provides rich structural
  comparisons, subtests, exception tools, and diagnostics.
- Test::More remains supported for established suites. Do not rewrite working
  tests merely to change imports.
- Do not hand-print TAP or mix frameworks/plugins with incompatible hubs.
- Every test asserts observable behavior and can fail for the intended defect.
- Use `done_testing` unless a fixed plan adds useful discipline.
- Keep tests independent of order, current directory, locale, timezone,
  environment, network, and wall clock unless those are the subject.

## 2. Test layout and include paths

- `t/` contains tests consumers must pass to install.
- `xt/author/` contains style, POD, spelling, and expensive developer checks.
- `xt/release/` contains release-only metadata, MANIFEST, portability, and
  generated-artifact checks.
- Test helpers belong under `t/lib` and are loaded explicitly; do not leak
  repository paths into distribution runtime.
- Use `prove -l` only when testing checkout `lib/`; test the built distribution
  separately to catch missing MANIFEST/generated files.

## 3. Determinism and isolation

- Use `File::Temp` for per-test directories/files and clean external resources.
- Localize `%ENV`, locale, timezone, signal handlers, separators, and globals.
- Inject clocks/RNGs; print and persist a seed for generated failures.
- Use ephemeral ports allocated by the OS, not fixed ports or sleep-based
  readiness.
- Roll back/reset databases and test actual DB/driver semantics for DBI code.
- Run shuffle and parallel modes to expose state leaks. Mark genuinely serial
  tests through harness rules rather than disabling parallelism globally.

## 4. Error and boundary coverage

Test:

- scalar/list/void context where API behavior differs;
- false vs undefined values and malformed/truncated bytes;
- file write/close failure, permissions, and platform path behavior;
- DB transaction rollback, constraints, deadlocks/timeouts, and reconnects;
- child exec failure, nonzero/signal exit, full pipes, and cancellation;
- injection payloads, traversal/symlink cases, deep/oversized structures,
  duplicate keys, and adversarial regex inputs;
- optional dependency absent/present and pure-Perl/XS paths.

## 5. Coverage

```bash
cover -delete
HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t
cover -report text
cover -report html
```

Run coverage in a dedicated modern-Perl job without profiler instrumentation.
Use branch/condition reports to find missing behavior in parsers, authorization,
errors, and cleanup. Coverage percentage is not proof of correctness and should
not incentivize low-value assertions.

## 6. Property and fuzz testing

Perl has no single dominant current property framework. Small deterministic
generators in Test2 subtests are often safer than adopting an unmaintained
foundation.

Useful properties include round trips, canonicalization idempotence, parser
totality, equivalence, transaction invariants, and path containment.

- Print seed and minimized input on failure; implement shrinking where useful.
- Bound generated size/depth/time/memory.
- For parsers and XS, expose a tiny stdin/bytes harness to AFL++/libFuzzer or
  another external fuzzer; use sanitizers for native code.
- Persist every minimized crash as a normal regression test.

## 7. Perl and platform CI matrix

Libraries should test:

- declared minimum Perl on Linux;
- current stable and previous stable Perl;
- macOS and Windows on at least one current Perl when claimed supported;
- threaded Perl when claimed supported or when XS/thread behavior matters;
- optional non-blocking development/blead job for early warning.

Applications may pin production Perl but should still test planned upgrades.
Use `shogo82148/actions-setup-perl` or the repository's equivalent, pin
third-party actions to commit SHAs in high-assurance CI, and print `perl -V`.

Each job installs clean dependencies and runs the canonical suite. Cache keys
include OS, interpreter configuration, and dependency manifests; caches are
acceleration, never the only dependency source.

## 8. Static and security CI gates

A new-project check shape is:

```bash
while IFS= read -r -d '' file; do
    perltidy -st --assert-tidy "$file" >/dev/null || exit
    perlcritic --profile .perlcriticrc "$file" || exit
done < <(git ls-files -z '*.pl' '*.pm' '*.t')
prove -lr t
cpan-audit --fresh --perl deps .
```

Adapt to the repository. Run dependency audit on a schedule because advisories
change without a commit. Never expose release credentials or other secrets to
fork pull-request code, and never combine `pull_request_target` privileges with
checkout/execution of untrusted PR content.

## 9. Author and release tests

```bash
AUTHOR_TESTING=1 prove -lr xt/author
RELEASE_TESTING=1 prove -lr xt/release
```

- Author-only dependencies do not burden consumer installs.
- Release checks run against the generated, unpacked tarball, not just the
  working tree.
- Validate META files, MANIFEST, license, Changes, executable bits, undeclared
  files, minimum Perl, clean install, and absence of secrets/build artifacts.
- Run the generated installer and tests in a clean environment before upload.
- Require an equivalent generated-tarball test. Dist::Zilla `[TestRelease]` is
  one option, not a mandatory plugin; authoring-tool success alone does not
  prove the tarball works.

## 10. CPAN release and provenance

Build once from a reviewed protected tag, test that exact artifact, calculate a
SHA-256 checksum, optionally attest/sign it, and upload the identical bytes to
PAUSE. Do not rebuild separately on a laptop after CI passed.

- Keep PAUSE credentials narrowly scoped and in a protected release
  environment.
- Separate release/upload from pull-request jobs and require all matrices.
- Publish Changes and preserve immutable tags/artifacts.
- Attestation proves origin/build linkage, not safety, and CPAN clients may not
  verify it automatically.
- Test install from the uploaded/retrieved artifact as a post-release smoke
  check; do not overwrite a released version.

## 11. CI baseline shape

```yaml
strategy:
  fail-fast: false
  matrix:
    perl: ["5.44", "5.42", "5.36"]

steps:
  - uses: actions/checkout@v4
  - uses: shogo82148/actions-setup-perl@v1
    with:
      perl-version: ${{ matrix.perl }}
  - run: perl -V
  - run: cpm install
  - run: PERL5LIB="$PWD/local/lib/perl5" prove -lr t
```

The tags and Perl versions above are executable examples, not a recommendation
to leave Actions unpinned or to claim a 5.36 floor. Replace them with current,
repository-appropriate values, including the project's actual minimum.

## Audit checklist

```bash
# Suite inventory and runner configuration
ls t xt/author xt/release 2>/dev/null
rg -n 'Test2::V0|Test::More|done_testing|subtest|skip_all|TODO|BAIL_OUT' t xt 2>/dev/null
rg -n '\bsleep\b|localhost:[0-9]+|srand|rand\b|time\b|%ENV|\$ENV\{' t --glob '*.t' 2>/dev/null

# Disabled/flaky/serial tests
rg -n 'SKIP|TODO|skip_all|HARNESS_RULES|prove .*--rules|retries|flaky' t xt .github .gitlab-ci.yml 2>/dev/null

# Coverage and quality/security gates
rg -n 'Devel::Cover|cover -|perltidy|perlcritic|cpan-audit|AUTHOR_TESTING|RELEASE_TESTING' .github .gitlab-ci.yml Makefile.PL dist.ini cpanfile 2>/dev/null

# Version/platform matrix and unsafe CI triggers
rg -n 'perl-version|actions-setup-perl|docker-perl|ubuntu|macos|windows|blead' .github .gitlab-ci.yml 2>/dev/null
rg -n 'pull_request_target|permissions:|id-token:|PAUSE|CPAN' .github 2>/dev/null

# Distribution artifact hygiene
rg -n 'TestRelease|distcheck|make dist|minil dist|dzil (build|test|release)|META\.json|MANIFEST' .github Makefile.PL dist.ini minil.toml xt 2>/dev/null
git ls-files | rg '(^|/)(local|blib|cover_db|nytprof|_build)/|\.pmat$|\.tar\.gz$'
```

Confirm claimed support from metadata and documentation before reporting a
missing matrix. Small internal applications do not need every CPAN release job.

## References

- https://perldoc.perl.org/prove
- https://metacpan.org/pod/Test2::V0
- https://perldoc.perl.org/Test::More
- https://metacpan.org/pod/Devel::Cover
- https://metacpan.org/pod/CPAN::Meta
- https://github.com/shogo82148/actions-setup-perl
