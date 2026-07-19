# 01 - Tooling, Project Setup, and Dependencies

Use modern defaults for greenfield work, but preserve an effective established
toolchain. Perl has several valid installers and authoring systems; consistency,
clean builds, and tested compatibility matter more than migration for its own
sake.

## 1. Supported Perl and compatibility floor

Perl stable series use even minor numbers; odd minors are development series.
Check `perlpolicy` before naming supported releases. New applications should
run on a current supported stable Perl. Libraries choose the oldest useful
floor and exercise it in CI.

```bash
perl -V
perl -e 'printf "%vd\n", $^V'
```

- Do not install application dependencies into an OS-owned system Perl.
- Pin the full patch release for deployed applications where practical.
- Record `perl -V` for XS-sensitive builds: architecture, threads, compiler,
  and build options are compatibility inputs.
- A version declaration, metadata prerequisite, documentation, and CI matrix
  must agree.

`perlbrew` is a reasonable new-project default for isolated interpreters;
`plenv`, containers, and CI-provided Perl are valid established choices.

```bash
perlbrew install perl-5.44.0
perlbrew switch perl-5.44.0

plenv install 5.44.0
plenv local 5.44.0
```

Verify the current release before copying those version examples.

## 2. cpanfile is dependency intent

Use `cpanfile` for application and distribution prerequisites unless existing
metadata generation is canonical.

```perl
requires 'perl', '5.036';
requires 'DBI', '>= 1.643, < 2.0';

on test => sub {
    requires 'Test2::V0';
};

on develop => sub {
    requires 'Perl::Tidy';
    requires 'Perl::Critic';
    requires 'CPAN::Audit';
};
```

- Bare module versions are minimums; exact pins use `==`.
- Runtime, test, configure/build, and develop dependencies belong in the
  correct phase/relationship.
- Avoid blanket upper bounds. Add one only for a demonstrated incompatible
  release line and document removal criteria.
- Core/dual-life status varies by Perl version. Declare what the minimum Perl
  actually needs, not what happens to exist on a developer machine.

## 3. Installation and reproducibility

For new projects, current `cpm` is a fast parallel installer:

```bash
cpm install
cpm install --test
PERL5LIB="$PWD/local/lib/perl5" prove -lr t
```

`cpm` does not run dependency tests by default and does not create a snapshot
by itself. Use `--test` when dependency tests are part of the assurance model.

For Carton applications, commit `cpanfile` and `cpanfile.snapshot`, ignore
`local/`, and deploy from a clean environment:

```bash
carton install
carton exec prove -lr t
carton install --deployment
```

Preserve Carmel where adopted. `cpanm` remains useful for bootstrap and simple
installs but is not a lock manager; require a current release and HTTPS mirror.

- Applications commit their repository's snapshot/lock and build cleanly from
  it. Do not rely on a developer's pre-populated `local/`.
- CPAN libraries publish dependency ranges; their development snapshot must
  not constrain downstream consumers.
- A snapshot pins resolution, not bytes, ABI, compiler, system libraries, or
  availability. High-assurance builds retain reviewed artifacts and hashes.
- Never use `--force` or `--notest` as routine CI policy.

## 4. Distribution authoring

Direct `ExtUtils::MakeMaker` is a transparent default with broad compatibility:

```bash
perl Makefile.PL
make
make test
make distcheck
make dist
```

Minilla is appropriate for conventional distributions that benefit from a
small authoring wrapper:

```bash
minil test
minil dist
```

Preserve Dist::Zilla when its plugin pipeline is established. It remains
actively maintained but its generated release can differ substantially from
the repository, so pin author dependencies and test the generated tarball.

- Do not add multiple competing metadata sources.
- Keep `META.json` authoritative in built distributions; `META.yml` exists for
  older clients.
- Generated `Makefile.PL`/`Build.PL` must be present and usable by consumers.
- Do not migrate EUMM, Minilla, Module::Build::Tiny, or Dist::Zilla during an
  unrelated feature change.

## 5. Layout and namespaces

Conventional distributions use:

```text
lib/Example/Widget.pm
script/example-widget
t/00-load.t
xt/author/
xt/release/
cpanfile
Makefile.PL
Changes
LICENSE
```

Package names and paths must match case exactly. Keep consumer tests in `t/`;
expensive style, metadata, spelling, and release-policy checks live in `xt/`.
Do not ship local installs, profiler output, coverage databases, secrets, or
editor artifacts.

## 6. perltidy and Perl::Critic

Commit `.perltidyrc` and pin the formatter version used in CI. Check without
rewriting using:

```bash
while IFS= read -r -d '' file; do
    perltidy -st --assert-tidy "$file" >/dev/null || exit
done < <(git ls-files -z '*.pl' '*.pm' '*.t')
```

Use the project's configured targets when present. The tracked-file command
avoids assuming that every repository has `lib/`, `script/`, and `t/`.

Use a committed `.perlcriticrc` with deliberately selected correctness,
maintenance, and security policies:

```bash
perlcritic --profile .perlcriticrc lib script
```

- Perl::Critic defaults are opinions, not the language specification.
- Introduce it progressively in legacy code; do not create a mass-reformat or
  suppression diff during focused work.
- `## no critic` names the policy, covers the smallest possible scope, and has
  a reason. Bare file-wide suppressions are debt, not compliance.
- Do not enable unsafe policies while scanning untrusted source.

## 7. Documentation and dependency review

Public modules need POD covering purpose, synopsis, public methods/functions,
parameters, context behavior, return values, exceptions, encoding, blocking,
and compatibility. Keep examples executable in tests when practical.

Every dependency addition requires review of:

- maintenance/release history and PAUSE permissions;
- transitive dependency and XS/native-code expansion;
- build scripts and bundled binaries;
- minimum Perl and platform support;
- license and security history.

## Audit checklist

Run from repository root and adapt paths to the project.

```bash
# Interpreter and declared floor
perl -V
rg -n '^use (v?5\.|[0-9]+\.[0-9]+)' --glob '*.{pl,pm,t}'
rg -n "perl.*=>|requires ['\"]perl" Makefile.PL Build.PL cpanfile dist.ini minil.toml META.json 2>/dev/null

# Dependency sources and reproducibility
ls cpanfile cpanfile.snapshot Carton.lock META.json Makefile.PL Build.PL dist.ini minil.toml 2>/dev/null
git ls-files | rg '(^|/)local/|\.carton/|nytprof|cover_db|\.pmat$'
rg -n -- '--force|--notest|cpanm .*http://' .github .gitlab-ci.yml Dockerfile* 2>/dev/null

# Tooling gates and suppressions
ls .perltidyrc .perlcriticrc 2>/dev/null
rg -n 'perltidy|perlcritic|prove|cpan-audit' .github .gitlab-ci.yml Makefile.PL dist.ini 2>/dev/null
rg -n '## no critic' --glob '*.{pl,pm,t}'

# Namespace/layout and generated distribution hygiene
rg -n '^package ' lib --glob '*.pm'
rg -n 'Dist::Zilla|Minilla|ExtUtils::MakeMaker|Module::Build' Makefile.PL Build.PL dist.ini minil.toml 2>/dev/null
```

Missing a particular tool is not automatically a finding. Confirm that the
repository lacks an equivalent enforced control.

## References

- https://perldoc.perl.org/perlpolicy
- https://metacpan.org/pod/cpanfile
- https://metacpan.org/pod/App::cpm
- https://metacpan.org/pod/Carton
- https://perldoc.perl.org/ExtUtils::MakeMaker
- https://metacpan.org/pod/Perl::Critic
