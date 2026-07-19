# 03 - Modules, APIs, Object Design, and Errors

Stable Perl APIs make context, mutation, ownership, errors, encoding, and
compatibility explicit. Dynamic flexibility belongs behind a small boundary,
not in every caller.

## 1. Module boundaries and exports

```perl
package Example::Parser;

use v5.36;
use Exporter 'import';

our $VERSION = '1.00';
our @EXPORT_OK = qw(parse_record);

sub parse_record ($text) {
    ...
}

1;
```

- Export nothing by default unless the module is intentionally a DSL.
- Prefer `@EXPORT_OK`; never export methods or mutable package variables.
- Load without imports using `use Module ();`.
- Prefer `use Exporter 'import'` over inheriting from Exporter.
- Keep `1;` for broad module compatibility even where `module_true` is active.
- One primary package per file; package and path case must match.
- Keep internal helpers lexical where practical and use a leading underscore
  for package-level implementation details.

## 2. Public API contracts

For each public function/method document and test:

- accepted types/shapes and validation boundary;
- scalar/list behavior and return shape;
- whether references are retained, aliased, copied, or mutated;
- exception classes/strings and recoverable conditions;
- byte vs character expectations and normalization;
- blocking, timeout, cancellation, retry, and idempotency behavior;
- thread/fork safety and global-state effects;
- minimum Perl and optional-feature behavior.

Use options hashes for evolving APIs, reject unknown keys, and avoid long
positional boolean lists. Additive optional keys are usually safer than
changing return context or tuple ordering.

## 3. Validation and domain data

Validate external shape at the boundary, then pass narrow domain values
inside. Do not carry raw request hashes throughout the application.

- Distinguish missing, undefined, empty, and zero where the domain does.
- Construct values in a valid state; avoid objects requiring a sequence of
  undocumented setter calls before use.
- Prefer immutable/read-only attributes unless mutation is part of the model.
- Return copies or read-only views where exposing internals would break
  invariants.
- Type::Tiny constraints are appropriate when runtime type contracts add
  value; do not turn every scalar into framework ceremony.

## 4. Object-system choice

Use the smallest stable mechanism that meets the need:

- A hand-written blessed hash is fine for a tiny dependency-free value object
  with a well-tested constructor.
- Moo is the greenfield production default when attributes, roles,
  inheritance, coercion, or validation are needed.
- Preserve Moose where its metaprogramming ecosystem is used.
- Core `class` remains experimental and has documented crash/corruption bugs
  in Perl 5.44; do not choose it for conservative production code yet.

```perl
package Example::User;

use v5.36;
use Moo;

has name => (
    is       => 'ro',
    required => 1,
);

sub greeting ($self) {
    return 'Hello ' . $self->name;
}
```

- Mutable defaults are coderefs: `default => sub { [] }`.
- Use coderef or Type::Tiny constraints deliberately; Moo has no implicit type
  language.
- Prefer roles to deep or multiple inheritance.
- Do not expose raw hash storage as public API or inspect another object's
  implementation directly.
- Avoid `AUTOLOAD` unless dynamic dispatch is the actual domain; it obscures
  typos, introspection, security review, and static analysis.

## 5. Error taxonomy

Use `Carp` for caller contract failures:

```perl
use Carp qw(croak confess);

sub parse ($input) {
    croak 'input must be defined' unless defined $input;
    ...
}
```

- `croak` attributes a public API misuse to the caller.
- `confess` is for invariant diagnostics where a stack is useful, not routine
  user-facing errors.
- `die` is appropriate for current-location application failure.
- Use typed exception objects only when callers need stable machine-readable
  classification; keep the hierarchy small and preserve causes.
- Never parse exception strings for business logic when an object or explicit
  result can carry the category.
- Report once at the boundary that can decide retry, response, or process exit;
  avoid logging and rethrowing at every layer.

## 6. Catching exceptions safely

On Perl 5.40+, native `try`/`catch` without experimental `finally` is stable:

```perl
use v5.40;

try {
    perform_operation();
}
catch ($error) {
    die $error unless recoverable($error);
}
```

For lower floors, preserve the project's Try::Tiny or Feature::Compat::Try
choice. Know their semantics; a Try::Tiny block is a callback, so `return`
does not return from the containing subroutine.

If raw `eval` is unavoidable:

```perl
my ($ok, $error);
{
    local $@;
    $ok = eval {
        perform_operation();
        1;
    };
    $error = $@;
}
die $error unless $ok;
```

- Use block `eval`, never string `eval`, for exception handling.
- Localize and capture `$@` immediately; other code and destructors can alter
  it, and an exception can stringify to a false value.
- Catch only errors the current layer can handle. Rethrow unknown exception
  objects without flattening them to strings.
- Do not silently convert failures to `undef` unless `undef` is a documented,
  unambiguous outcome.

## 7. Cleanup and transactions

- Prefer lexical resource ownership and small scopes.
- Use explicit database transaction commit/rollback and test both paths.
- A destructor must not throw during global destruction; make cleanup
  idempotent and tolerate partially constructed objects.
- Do not rely on destruction timing for correctness, especially with cycles,
  forks, interpreter shutdown, or async resources.
- Scope guards are useful for local rollback, but process death still requires
  external transactional/idempotent design.

## 8. Logging and diagnostics

- Libraries do not configure global logging; applications own handlers,
  levels, destinations, and structured context.
- Separate operator diagnostics from CLI output. Output goes to STDOUT;
  diagnostics go to STDERR/logging.
- Include operation and stable identifiers, not secrets or entire request
  payloads.
- Preserve the original exception/cause and stack where useful.
- Bound and sanitize user-controlled fields to prevent multiline/terminal log
  injection; structured fields are preferable to interpolated prose.

## 9. Compatibility and release discipline

Public CPAN module behavior includes exports, method signatures, accepted
input, return context, exceptions, metadata, feature flags, and minimum Perl.

- Deprecate before removal and provide a migration path.
- Do not silently raise minimum Perl through syntax or dependency updates.
- Test optional dependency absence and each supported feature combination.
- Avoid compile-time loading of heavy optional modules; require them at the
  feature boundary and produce an actionable error.
- Keep generated release source and repository source differences reviewable.

## Audit checklist

```bash
# Exports, globals, dynamic dispatch, and object systems
rg -n '@EXPORT\b|@EXPORT_OK|use parent ['"'"']Exporter|use base ['"'"']Exporter' lib --glob '*.pm'
rg -n '^\s*(our|local)\s+[\$@%]' lib --glob '*.pm'
rg -n '\bAUTOLOAD\b|can\(\$|->\$\w+|bless\b|use (Moo|Moose)\b|feature ['"'"']class' lib --glob '*.pm'

# Error handling and swallowed failures
rg -n '\beval\s*\{|\btry\s*\{|Try::Tiny|Feature::Compat::Try|\$@' --glob '*.{pl,pm,t}'
rg -n 'eval\s*\{[^}]*\};\s*$|warn\s+\$@|return\s+undef|or\s+return\b' --glob '*.{pl,pm,t}'
rg -n '\b(DESTROY|DEMOLISH)\b|\bdie\b|\bcroak\b|\bconfess\b' lib --glob '*.pm'

# Mutable defaults and representation exposure
rg -n "default\s*=>\s*[\[{]|sub\s+new\b|\{\$self\}|\$self->\{" lib --glob '*.pm'

# POD/API surface
rg -n '^=head[12]|^=method|^=func|^=item' lib --glob '*.pm'
rg -L '^=head1 (NAME|SYNOPSIS|DESCRIPTION)' lib --glob '*.pm'
```

Review each hit in context. A blessed hash, package variable, `AUTOLOAD`, or
`undef` result can be intentional; the finding is an unsafe or undocumented
contract, not the token itself.

## References

- https://perldoc.perl.org/perlmod
- https://perldoc.perl.org/Exporter
- https://metacpan.org/pod/Moo
- https://perldoc.perl.org/perlclass
- https://perldoc.perl.org/Carp
- https://perldoc.perl.org/perlsyn#Try-Catch-Exception-Handling
