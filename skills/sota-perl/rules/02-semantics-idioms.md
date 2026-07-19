# 02 - Semantics, Idioms, and Language Pitfalls

Perl's power comes from context, coercion, references, regexes, and dynamic
features. Production code makes those semantics visible rather than relying on
clever defaults.

## 1. Stable feature bundles

Use a version declaration supported by the project:

```perl
use v5.36;
```

Perl 5.36+ bundles enable strictness, warnings, stable signatures, and `isa`.
Later bundles add or remove stable features. Feature bundles are lexical and
fixed by minor release.

- Never use `use feature ':all'`; future interpreters can enable experimental
  or behavior-changing features.
- Core `class`, named signature parameters, `finally`, `defer`, reference
  aliasing, and keyword `all`/`any` remain experimental in Perl 5.44. Do not
  use them in conservative production code without explicit user acceptance,
  warning suppression, compatibility tests, and an exit plan.
- Avoid `given`/`when` and smartmatch in new code.
- Libraries must not use `warnings FATAL => 'all'`; future warning categories
  can turn an interpreter upgrade into a downstream outage.
- On older floors, use explicit `use strict; use warnings;` as needed.

## 2. Signatures and arguments

Use stable positional signatures when the floor is 5.36+:

```perl
sub clamp ($value, $min, $max = 100) {
    return $min if $value < $min;
    return $max if $value > $max;
    return $value;
}
```

- Signature variables are copies; legacy `@_` elements are aliases.
- Do not access `@_`, `$_[0]`, bare `shift`, or bare `pop` inside a signatured
  subroutine.
- `//=` defaults omitted or undefined values; `||=` also overwrites valid
  false values such as `0` and `''`.
- Use slurpy arrays/hashes deliberately and validate unknown named options.
- Prototypes are not signatures. Introduce them only for intentional parser-
  like call syntax and document their compile-time behavior.

## 3. Context is an API contract

Scalar, list, and void context can change both result and work performed:

```perl
my @rows  = fetch_rows();
my $count = () = fetch_rows();
my $value = scalar fetch_rows();
```

- There is no universal relationship between scalar and list returns.
- Parenthesized lists in scalar context return their last element.
- Arrays return their size in scalar context; flattening destroys nested
  structure in argument and return lists.
- `map`, `grep`, regex `/g`, `stat`, `localtime`, and many DB APIs vary by
  context. Document the chosen behavior and test both contexts if supported.
- Avoid surprising context-sensitive public APIs. Prefer array/hash references
  for structured data.
- Do not write `my ($line) = <STDIN>` when one line is intended: list context
  can consume all input. Use `my $line = <STDIN>`.

## 4. Definedness, truth, and comparison

Perl false values include `undef`, `0`, `"0"`, and `""`.

```perl
my $port = defined $input ? $input : 443;
my $name = $input // 'anonymous';
```

- Use `defined`/`//` when zero or empty string is valid.
- Use `eq`, `ne`, `lt`, and `gt` for strings; `==`, `!=`, `<`, and `>` for
  numbers. Accidental coercion often appears to work until data changes.
- Check regex success with the match result, not `$1` truthiness; captures may
  validly contain `0` or empty string.
- Use `exists` to distinguish a missing hash key from a present undefined
  value.

## 5. References, ownership, and autovivification

Use hard references and explicit dereferencing:

```perl
my $config = {servers => [{host => 'example.test'}]};
my $host = $config->{servers}->[0]->{host};
my @servers = $config->{servers}->@*;
```

- Never enable symbolic references for names derived from data; use a dispatch
  hash of coderefs or objects.
- Autovivification is desirable for intentional writes but surprising during
  traversal. Validate reference types before deep access at trust boundaries.
- Break cycles with `Scalar::Util::weaken` on the deliberate non-owning edge.
- Do not use stringified references as durable IDs; assign explicit stable IDs
  or use a reference-keyed facility.
- Copy or clone only when ownership semantics require it. Document whether an
  API aliases, mutates, or retains a caller-provided reference.

## 6. Lexical scope and globals

- Prefer `my` and `state`; reserve `our` for package API/version/export state.
- `local` temporarily changes a package variable's value through dynamic
  scope; it does not create a lexical. Use it for `%ENV`, `@INC`, special
  variables, and narrow compatibility hooks only.
- Avoid action at a distance through package globals, localized separators,
  default `$_`, and implicit handles in reusable code.
- Use `state` for process-local caches only when lifetime, invalidation,
  memory bounds, fork behavior, and test reset are understood.

## 7. Filehandles and resources

Use lexical handles and explicit layers:

```perl
open my $input, '<:encoding(UTF-8)', $path
    or die "cannot open $path: $!";

open my $blob, '<:raw', $path
    or die "cannot open $path: $!";
```

- Three-argument `open` prevents filenames from becoming modes or commands.
- Check `open`, writes, and `close`; close can surface buffered write and pipe
  failures.
- Use `File::Temp` for temporary files and automatic cleanup. Never use
  `mktemp` or check-then-create.
- Lexical destruction is useful but not a transaction guarantee. Commit or
  roll back external state explicitly.

## 8. Unicode boundary discipline

Decode bytes at input, process characters internally, encode at output:

```perl
use Encode qw(decode encode FB_CROAK);

my $text = decode('UTF-8', $bytes, FB_CROAK);
my $wire = encode('UTF-8', $text, FB_CROAK);
```

- `use utf8` declares source-code encoding; it does not configure I/O.
- Prefer `:encoding(UTF-8)` over `:utf8`; the latter does not validate bytes.
- Reject malformed external input unless replacement is an explicit product
  requirement.
- Normalize at one documented boundary when canonical equivalence matters.
  Normalization form is domain-specific and does not prevent confusables.
- `length` counts code points, not user-perceived grapheme clusters; use `\X`
  when graphemes are the domain unit.
- Use `/aa` or explicit ASCII classes for ASCII protocols and identifiers.

## 9. Regex clarity and correctness

- Use `qr//` for reusable patterns and `/x` or `/xx` for complex expressions.
- Use `\A` and `\z` for whole-string validation; `^` and `$` have line
  semantics and `$` can match before a final newline.
- Quote data inserted into patterns with `quotemeta` or `\Q...\E`.
- Avoid global match state shared across calls and implicit `$1` dependencies;
  use named captures and consume them immediately.
- A successful validation regex must allowlist the complete accepted grammar,
  not merely remove known bad characters.

## 10. Readability over cleverness

- Use `map`/`grep` to produce values, not for side effects.
- Parenthesize ambiguous list operators and mixed-precedence expressions.
- Prefer explicit arguments over hidden defaults in reusable code.
- Use `or` for statement-level failure handling only; use parentheses and
  `||` inside expressions.
- Keep complex transformations in named subroutines and label nested loops
  when labels clarify multi-level `next`/`last` behavior.

## Audit checklist

```bash
# Compile under the project's interpreter and include paths
perl -Ilib -c path/to/changed.pm
while IFS= read -r -d '' file; do
    perl -Ilib -c "$file" || exit
done < <(git ls-files -z '*.pl' '*.pm' '*.t')

# Missing version/strictness and experimental features
rg -L '^use (v?5\.|strict)' --glob '*.{pl,pm}' lib script 2>/dev/null
rg -n "feature ['\"](:all|class|defer|refaliasing|declared_refs|keyword_(all|any))|experimental::" --glob '*.{pl,pm,t}'
rg -n '\b(given|when)\b|~~' --glob '*.{pl,pm,t}'

# Context, truthiness, and comparisons: review, do not report from grep alone
rg -n 'my \([^)]*\)\s*=\s*<|scalar\s+\w+\(|wantarray|\b(map|grep)\s*\{' --glob '*.{pl,pm,t}'
rg -n "\$\w+\s*(==|!=)\s*['\"]|\$\w+\s+(eq|ne)\s+\d" --glob '*.{pl,pm,t}'
rg -n '\|\|=' --glob '*.{pl,pm,t}'

# Dynamic features and file handling
rg -n "no strict ['\"]refs|\$\{\$|&\{|->\$\w+" --glob '*.{pl,pm,t}'
rg -n '\bopen\s*\([^,]+,[^,]+\)|\bopen\s+[^,]+,\s*[^,;]+;' --glob '*.{pl,pm,t}'
rg -n '>:utf8|<:utf8|use utf8' --glob '*.{pl,pm,t}'

# Regex whole-string and interpolation review
rg -n '=~\s*m?[{/].*\$|\^.*\$|\$\w+.*[+*}]' --glob '*.{pl,pm,t}'
```

The bulk compile command may need repository-specific include paths, generated
modules, or dependency setup. Do not classify environmental failures as source
defects.

## References

- https://perldoc.perl.org/feature
- https://perldoc.perl.org/perldata
- https://perldoc.perl.org/perlsub
- https://perldoc.perl.org/perlref
- https://perldoc.perl.org/perlunicode
- https://perldoc.perl.org/perlre
