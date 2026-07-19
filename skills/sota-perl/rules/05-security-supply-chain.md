# 05 - Security and Supply Chain

Treat network input, command-line arguments, environment, files, database
content, queue messages, and plugin/module metadata as untrusted until a narrow
boundary validates them. Perl's dynamic features make data-to-code transitions
especially important to audit.

## 1. Taint mode is a tripwire, not a sandbox

`perl -T` can catch dangerous data flow in privileged/server scripts, but it is
neither necessary nor sufficient security.

- Hash keys are not tainted; output via `print`/`syswrite` is not checked.
- Symbolic methods/sub references can bypass the intended control.
- Reading an attacker-selected file may be allowed.
- Regex captures untaint regardless of whether the pattern validates safely.
- `sudo` does not automatically enable taint mode, and Perl can be built
  without taint support.
- Taint does not limit CPU, memory, filesystem, network, or malicious code.
- Core `Safe` compartments are not a robust isolation boundary. Use an OS
  sandbox/worker for untrusted code.

If taint is used, untaint only through an anchored allowlist grammar and set a
known environment before subprocesses:

```perl
local %ENV = (
    PATH => '/usr/bin:/bin',
    LANG => 'C',
);
```

## 2. Command and argument injection

Never invoke a shell with variable data:

```perl
system {$program} $program, '--', @args;
die "command failed: $?" if $? != 0;

open my $pipe, '-|', $program, '--', @args
    or die "spawn failed: $!";
```

- Avoid `system $string`, one-argument `exec`, backticks, `qx//`, shell pipe
  opens, `sh -c`, and `open3` command strings on untrusted data.
- Allowlist or fix executable paths; PATH lookup is a trust decision.
- Insert `--` before user-controlled operands when the program supports it.
- Add deadlines, output-size limits, a minimal environment, least privilege,
  and checked exit/signal status.
- An argv list prevents shell injection, not option injection or vulnerabilities
  in the invoked program.

## 3. File and path safety

Two-argument `open` can interpret a filename as a mode or command. Use lexical
handles and three-argument `open` exclusively for variable paths.

Path containment is harder than string prefixes:

- Prefer opaque logical IDs mapped to server-owned paths.
- Reject NUL, absolute paths, alternate volumes/UNC paths, empty or parent
  components, and platform separator variants as appropriate.
- Resolve and compare path components against an existing trusted base.
- Do not authorize with `-e`/`-l` and later reopen by pathname; that is TOCTOU.
- Avoid attacker-writable parents. Use descriptor-relative OS APIs or
  `O_NOFOLLOW` where the threat requires them.
- For exclusive creation use `sysopen` with `O_CREAT|O_EXCL`, restrictive
  permissions, and a trusted parent; `O_EXCL` does not secure parent symlinks.
- Archive extraction requires member-count, path, type/link, and total decoded-
  size limits before writing.

`File::Spec->canonpath` and `no_upwards` are portability helpers, not a
security boundary.

## 4. SQL and DBI

Bind all values:

```perl
my $sth = $dbh->prepare(
    'SELECT id FROM users WHERE email = ? AND tenant_id = ?'
);
$sth->execute($email, $tenant_id);
```

- Placeholders cannot bind identifiers. Map authorized choices to a fixed
  table/column allowlist; quoting is not authorization.
- Configure `RaiseError => 1`, `PrintError => 0`, and deliberate AutoCommit.
- Use explicit transactions and rollback on every failure path.
- Use least-privilege DB accounts and driver/database statement timeouts.
- Avoid traces or error logs that expose credentials, SQL secrets, or bind
  values.

## 5. Code execution and deserialization

Critical trust-boundary bans:

- string `eval`, `evalbytes`, `s///ee`, generated `require`, or dynamic module
  names from untrusted data;
- Storable `retrieve`, `thaw`, or `$Storable::Eval` on external data;
- YAML Perl/object tags, custom classes, includes, or arbitrary constructors;
- loading plugins or source filters selected by untrusted input.

Use strict data formats, schema/shape validation, and limits on bytes, nesting,
keys, aliases, and collection sizes. For YAML, select a data-only schema and
reject duplicate keys/cycles. JSON syntax safety does not supply a schema or
resource limits.

Block `eval {}` is exception handling and is not the same risk as string eval.

## 6. Regex denial of service

Perl's backtracking regex engine can consume exponential time.

- Avoid nested/overlapping repetition such as `(a+)+`, ambiguous alternation
  under repetition, and unbounded `.*` before complex suffixes.
- Bound input before matching; anchor validation with `\A`/`\z`.
- Quote user literals and use bounded/negated classes, possessive quantifiers,
  or atomic groups only after semantic tests.
- Process hostile complex patterns in a disposable, resource-limited worker.
  `alarm` may not interrupt a long opcode promptly.
- RE2 adapters have semantic/Unicode differences and may fall back to Perl
  unless strict mode is enabled; verify rather than assuming safety.

## 7. Unicode and protocol security

- Decode UTF-8 strictly with `FB_CROAK`; do not use lax `UTF8` decoding for
  hostile interchange data.
- Normalize identifiers once before uniqueness/authorization comparisons, but
  handle mixed scripts and confusables separately.
- Use `/aa` or explicit ASCII classes for protocols that require ASCII;
  Unicode `\d` and `\w` match more than ASCII.
- Reject CR/LF/control characters in values placed into headers, logs, SMTP,
  Redis, or other line protocols.
- Treat filenames as platform-specific byte/character interfaces; do not
  assume text normalization matches filesystem identity.

## 8. Secrets and cryptography

- Source, cpanfile, snapshots, command lines, logs, DBI traces, test fixtures,
  profiler output, heap dumps, CI artifacts, and broad `%ENV` inheritance are
  all leak surfaces.
- Obtain secrets from a secret manager or narrow environment injection; redact
  by construction and rotate any exposed value.
- Use operating-system CSPRNG-backed maintained modules for tokens; never
  `rand`.
- Use maintained password-hashing and crypto libraries; no custom crypto,
  raw fast hashes for passwords, ECB, fixed nonces, or timing-sensitive `eq`
  comparisons for authenticators.
- Set restrictive permissions and artifact retention; crash/profiler data can
  contain plaintext secrets.

## 9. CPAN supply-chain controls

Installing a CPAN distribution executes build scripts and often tests/XS code.
Do it unprivileged in an isolated builder, not in a secret-rich production
runtime.

- Use current clients and HTTPS-only mirrors. cpanminus through 1.7047 had an
  insecure HTTP-download advisory; require 1.7048+ if cpanm is used.
- Never bootstrap with unauthenticated `curl | perl`.
- Review PAUSE permissions/maintainers, release history, build files, native
  code, bundled artifacts, and transitive dependency diffs.
- Applications deploy exact snapshots in clean matching environments; retain
  reviewed artifacts/hashes where stronger provenance is required.
- Update CPAN::Audit/CPANSA::DB frequently; it works from a bundled advisory
  database and detects known issues only. `--fresh` checks database age; it
  does not download new advisories.

```bash
cpan-audit --fresh --perl deps .
cpan-audit installed local/
```

Run dependency audit on schedule as well as pull requests; advisories appear
without dependency changes.

## 10. Network and parser edges

- Set request/body, header, nesting, decoded-size, and processing-time limits.
- Validate server-fetched URLs against scheme/host/address policy and recheck
  redirects to prevent SSRF and DNS rebinding.
- Verify TLS; use an explicit trust store rather than disabling verification.
- Bound decompression ratio/output, image dimensions, archive members, and
  parser recursion.
- XML parser safety depends on module configuration; disable external entities,
  DTD/network access, and expansion for untrusted documents.
- Authenticate webhooks over the exact raw bytes, compare MACs in constant
  time, enforce freshness, and make replay handling explicit.

## Audit checklist

```bash
# Taint and environment controls
rg -n '^#!.*perl.*-T|\b-T\b|local %ENV|\$ENV\{(PATH|IFS|CDPATH|ENV|BASH_ENV)\}' --glob '*.{pl,pm,t}'

# Commands and dangerous open forms [HIGH/CRITICAL after data-flow confirmation]
rg -n '\b(system|exec)\s+[^({]|`[^`]*\$|qx[/({].*\$|sh\s+-c|open\s+.*[|]' --glob '*.{pl,pm,t}'
rg -n '\bopen\s*\([^,]+,[^,]+\)|\bopen\s+[^,]+,\s*[^,;]+;' --glob '*.{pl,pm,t}'

# Code execution/deserialization [CRITICAL on untrusted data]
rg -n 'eval\s+[^\{]|evalbytes|s[/!#].*[/!#].*[/!#][a-z]*e|Storable|\b(thaw|retrieve)\b|YAML|require\s+\$' --glob '*.{pl,pm,t}'

# SQL construction and DBI policy
rg -n '(prepare|do|select\w*)\s*\([^)]*(\$|\.|sprintf)|DBI->connect|RaiseError|PrintError|AutoCommit' --glob '*.{pl,pm,t}'

# Paths, temporary files, archives
rg -n 'canonpath|rel2abs|realpath|abs_path|\.\./|extract|Archive::|mktemp|tmpnam|sysopen|O_NOFOLLOW|O_EXCL' --glob '*.{pl,pm,t}'

# Regex/Unicode/secret surfaces
rg -n '\([^)]*[+*][^)]*\)[+*]|\.\*[+*]?|qr.*\$|decode_utf8|decode\([^,]*UTF8|use utf8' --glob '*.{pl,pm,t}'
rg -ni "(api[_-]?key|secret|password|token)\s*=>?\s*['\"][^'\"]{8,}" --glob '*.{pl,pm,t,json,yaml,yml}'
rg -n '\brand\b|Digest::(MD5|SHA).*password|verify_hostname\s*=>\s*0' --glob '*.{pl,pm,t}'

# Supply chain and audit enforcement
rg -n 'cpan-audit|CPAN::Audit|cpanm|cpm install|carton install' .github .gitlab-ci.yml Dockerfile* cpanfile 2>/dev/null
rg -n 'http://.*cpan|curl.*\|.*perl|--force|--notest' . --glob '!local/**'
```

Do not report a regex, `eval`, DBI call, or dynamic require without tracing the
source and mitigations. Block eval is not string eval.

## References

- https://perldoc.perl.org/perlsec
- https://security.metacpan.org/
- https://security.metacpan.org/2025/06/06/two-arg-open.html
- https://perldoc.perl.org/Storable#SECURITY-WARNING
- https://metacpan.org/pod/DBI#Placeholders-and-Bind-Values
- https://github.com/briandfoy/cpan-audit
