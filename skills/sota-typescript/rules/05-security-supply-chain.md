# 05 — Security & Supply Chain

TypeScript-specific security mechanics and the npm dependency graph.
Cross-language security architecture — threat modeling, authn/authz design,
crypto selection, trust-boundary theory — belongs to `sota-code-security`;
load it for anything beyond the language-level patterns here.

The single highest-value rule: **types do not validate anything at runtime**.
Every input below is `unknown` until a schema parses it (`rules/02` §2.7).

## 5.1 Injection: never build a command, path, query, or URL by concatenation

**Subprocesses.** Pass an argument array; never build a shell string.

```ts
// BAD — shell metacharacters in `name` are code
exec(`convert ${name} out.png`);

// GOOD — no shell, arguments stay data
await Bun.spawn(["convert", name, "out.png"]).exited;   // or execFile / spawn
```

If a shell is genuinely required, the argument is still not safe to interpolate
— validate it against an allowlist first. Prefix user operands with `--` so a
value starting with `-` cannot become a flag, and use absolute executable paths
where `PATH` is not trusted.

**SQL.** Parameterize values, always. Identifiers (table/column names) cannot
be parameterized — resolve them through an allowlist map, never string
interpolation. Tagged-template SQL clients and query builders parameterize by
default; a template literal handed to a raw `query()` does not.

**Filesystem paths.** Resolve, then verify containment:

```ts
const full = path.resolve(baseDir, userPath);
if (full !== baseDir && !full.startsWith(baseDir + path.sep)) {
  throw new ForbiddenError("path escapes base directory");
}
```

Checking for `".."` in the input is not sufficient — encodings, absolute paths,
and symlinks all bypass it. Reject NUL bytes explicitly.

**Temp files.** A predictable name in a shared directory is a race and a
symlink-planting target. Create a private directory with an unpredictable
name, then create files inside it exclusively:

```ts
const dir = await fs.mkdtemp(path.join(os.tmpdir(), "job-"));
await fs.chmod(dir, 0o700);
await fs.writeFile(path.join(dir, "out.bin"), data, { flag: "wx", mode: 0o600 });
// ... use it, then
await fs.rm(dir, { recursive: true, force: true });   // in finally
```

- Never `/tmp/<fixed-name>` and never check-then-create (`exists` then write);
  the `wx` flag makes the create fail if the path already exists, so the check
  and the create are one step.
- `mode` only applies to a file the call creates, so pair it with `wx`.
- Remove the directory in a `finally`; crash-leftover temp data is still data
  at rest.

**Outbound URLs (SSRF).** A user-supplied URL is a request your server makes
with your network position. Parse with `new URL()`, allowlist the scheme
(`https:` only) and the host, resolve the hostname and reject loopback,
link-local (including cloud metadata endpoints), private, CGNAT, and multicast
ranges — and **re-validate after every redirect**, or set `redirect: "manual"`
and handle them yourself.

## 5.2 Dynamic code execution

`eval`, `new Function`, `vm` without isolation, and `import()` with a
runtime-computed specifier all execute data as code.

- Never pass request, config-file, or database content into any of them.
- Template engines that compile strings, and expression evaluators for
  user-supplied rules, are the same hazard wearing a library. If users must
  supply logic, use a sandboxed evaluator with no host access and a step limit
  — see `sota-sandboxing`.
- `JSON.parse` is safe; **`JSON.parse` with a reviver that assigns into an
  object is not** (§5.4).

## 5.3 Untrusted output: XSS and the DOM

- **Never assign untrusted data to `innerHTML`, `outerHTML`,
  `insertAdjacentHTML`, or `document.write`.** Use `textContent`, or sanitize
  with a maintained sanitizer if HTML is genuinely required.
- In React, `dangerouslySetInnerHTML` is the same sink with a warning in the
  name. In every framework, the "raw"/"unescaped" directive is the sink.
- **URLs are a sink too**: `href`/`src` accepting `javascript:` or `data:` from
  user input is XSS. Allowlist the scheme.
- Server-rendered JSON embedded in a `<script>` must escape `<` — otherwise a
  string containing `</script>` breaks out.
- Set a Content-Security-Policy; it is the backstop for the sink you missed.
- `postMessage` handlers must verify `event.origin` against an allowlist before
  trusting the payload.

## 5.4 Prototype pollution

Assigning attacker-controlled keys into an object can reach `Object.prototype`
and change behavior program-wide.

```ts
// BAD — key comes from a request body; "__proto__" poisons every object
for (const [k, v] of Object.entries(input)) target[k] = v;

// GOOD — Map has no prototype chain to pollute
const target = new Map(Object.entries(input));

// or, if an object is required
const target = Object.create(null);
if (k === "__proto__" || k === "constructor" || k === "prototype") continue;
```

- Deep-merge, `set`-by-path, and query-string parsing utilities are the classic
  vectors — prefer maintained libraries with explicit prototype guards.
- Validate with a schema that rejects unknown keys (`rules/02` §2.7) before any
  merge; that closes both this and mass assignment.
- `Object.freeze(Object.prototype)` at startup is a cheap defense in depth.

## 5.5 Secrets, config, and data exposure

- **Never commit secrets**; load from the environment or a secret manager and
  validate at startup (`rules/02` §2.7).
- **Client bundles are public.** Anything reaching browser code — including
  every `NEXT_PUBLIC_`/`VITE_`-prefixed variable — is published. Server-only
  secrets must be unreachable from client entry points.
- Sourcemaps published to production expose source; ship them to your error
  tracker instead.
- **Do not log secrets, tokens, or full request bodies.** Redact at the logger,
  not at each call site — see `sota-observability`.
- Errors returned to clients carry stack traces and SQL fragments if you let
  them. Return a code and a correlation id; log the detail server-side.
- Compare secrets with a constant-time function, never `===`.
- **A secret must not print by value.** Default stringification is the leak:
  `console.log(obj)`, `util.inspect`, `JSON.stringify`, `` `${value}` ``, and
  an error's stack or `cause` chain (`util.inspect` serializes `cause`
  recursively) all dump whatever the object holds. HTTP-client errors are the
  usual carrier — axios exposes the request `config`, headers included, through
  `error.config` and `error.toJSON()`.

```ts
const INSPECT = Symbol.for("nodejs.util.inspect.custom");

class Secret {
  readonly #value: string;
  constructor(value: string) { this.#value = value; }
  reveal(): string { return this.#value; }
  toJSON(): string { return "[REDACTED]"; }
  toString(): string { return "[REDACTED]"; }
  [INSPECT](): string { return "Secret([REDACTED])"; }
}
```

  - Hold tokens, keys, and passwords in such a wrapper from the moment they are
    read from env or a vault; unwrap with `reveal()` only at the call that
    sends them. Bun documents `Bun.inspect.custom` as identical to Node's
    inspect hook.
  - Redact in the logger **and** at the point an error is serialized into a
    response, a log line, or an error-tracker payload. Log a picked subset of
    an HTTP error (`status`, `code`, `message`) rather than the error object.
  - Never put secrets in URLs or query strings — they land in access logs,
    `Referer` headers, and `error.config.url`. Send them in a header or body.

## 5.6 Dependency and supply-chain hygiene

npm is the largest attack surface most TypeScript projects have.

- **Commit the lockfile and install frozen in CI** (`rules/01` §1.7). Without
  it, a compromised or substituted version installs silently.
- **Install scripts execute arbitrary code at install time**, on developer
  laptops and CI runners with credentials. Audit them; run with install scripts
  disabled where the toolchain supports it, and allowlist the few packages that
  genuinely need them.
- **Vet before adding.** Check download trend, maintenance, maintainer count,
  and transitive weight. A one-function dependency that pulls twelve packages
  is a bad trade — see `rules/03` §3.9 for the platform APIs that replace most
  of them.
- **Pin exactly for applications** (the lockfile does this); publish ranges for
  libraries. Review dependency-bump diffs rather than auto-merging them.
- **Run `audit`/SCA in CI**, triaged by reachability rather than raw CVE count.
  A vulnerability in a build-only dependency is not the same finding as one in
  a request path.
- Prefer packages that publish **provenance/attestations**, and be suspicious
  of a package whose repository does not match its published contents.
- Typosquatting and slopsquatting are live: verify the exact package name
  before adding, especially for a name suggested by a model rather than found
  in documentation.

## 5.7 Denial of service

- **Regex**: nested quantifiers over user input backtrack catastrophically.
  Avoid `(a+)+`-shaped patterns, prefer explicit parsing, and **escape any
  user-supplied substring** before embedding it in a pattern.
- **`RegExp` is a backtracking engine**, so ReDoS is possible in any pattern
  with ambiguous repetition, not only the obvious ones. Cap input length
  before matching, and for patterns or inputs you do not control use a
  linear-time matcher or a real parser. Never `new RegExp(userText)`; escape
  with `RegExp.escape()` (runtime floor permitting) or a vetted helper.
- **A validation regex must cover the whole input.** `.test()` and `.match()`
  succeed on any substring, so `/\d+/.test("x1x")` is `true`; anchor with both
  `^` and `$`. The `m` flag makes `^`/`$` match at every line boundary, so
  `/^\d+$/m.test("abc\n123")` is `true` — no `m` on validators.
- **Body and upload limits** are enforced while streaming, not after buffering
  (`rules/04` §4.6). Also limit JSON nesting depth and array lengths in the
  schema.
- **Decompression bombs**: cap the decompressed size and abort past the limit.
- **Rate limit per account and per object**, not only per IP — see
  `sota-code-security`.
- Bound every fan-out and every queue (`rules/04` §4.2); unbounded concurrency
  is a self-inflicted DoS.

## 5.8 Runtime hardening

- Run as a non-root user in the container; drop capabilities. `sota-sandboxing`
  owns the isolation model.
- Use the runtime's permission flags (Deno's, Bun's, Node's permission model)
  where available to deny filesystem and network access the process does not
  need.
- Never set `NODE_TLS_REJECT_UNAUTHORIZED=0`, including "temporarily" in a
  development script that will be copied into a Dockerfile.
- Keep the runtime patched; a pinned base image that never moves accumulates
  known CVEs.
- **No debug surface in production.**
  - The inspector (`--inspect`, `--inspect-brk`, `--inspect-wait`) is remote
    code execution for whoever can connect. It defaults to `127.0.0.1:9229`;
    never pass a non-loopback host such as `0.0.0.0`, and keep the port out of
    `EXPOSE`, port mappings, and security-group rules.
  - Debug flags and dev mode (`NODE_ENV` other than `production`, `DEBUG`-style
    switches, verbose-error middleware) must not be the deployed default —
    derive them from validated config, defaulting to off.
  - Clients get an error code and a correlation id, never a stack trace
    (§5.5).
  - Production bundles do not carry public source maps: bundler `sourcemap` is
    `none` for browser output, or the `.map` files go to the error tracker and
    are excluded from the deployed static directory.

## Audit checklist

- [ ] Shell interpolation:
      `rg -n 'exec\(|execSync\(|\$\{.*\}.*\bshell\b|spawn\(.*shell:\s*true' --glob '**/*.ts'`
      with template literals → CRITICAL when reachable from input.
- [ ] Dynamic code: `rg -n '\beval\(|new Function\(|vm\.runIn' --glob '**/*.ts'`
      → CRITICAL if data flows in.
- [ ] SQL by concatenation:
      `rg -n '(query|execute)\(\s*[\x60\x27"].*\$\{' --glob '**/*.ts'` → CRITICAL.
- [ ] Path traversal: `rg -n 'path\.join\([^)]*\b(req|request|params|query|body)\b'`
      → HIGH unless followed by a containment check.
- [ ] SSRF: `rg -n 'fetch\((?!["\x27]https?://)' --pcre2 --glob '**/*.ts'` where
      the URL derives from input, with no host allowlist → HIGH.
- [ ] XSS sinks: `rg -n 'innerHTML|outerHTML|insertAdjacentHTML|dangerouslySetInnerHTML|document\.write'`
      → HIGH each unless the value is provably static or sanitized.
- [ ] Unchecked `postMessage`: `rg -n "addEventListener\('message'" -A5` without
      an `origin` check → HIGH.
- [ ] Prototype pollution: `rg -n '\[\s*(key|k|prop|name)\s*\]\s*=' --glob '**/*.ts'`
      in merge/assign helpers over request data → HIGH; also
      `rg -n 'merge\(|deepMerge\(|set\(.*path'`.
- [ ] Mass assignment: object spread of a request body into a persisted entity
      (`rg -n '\.\.\.(req\.body|body|input|payload)'`) → HIGH.
- [ ] Secrets in the repo:
      `rg -in '(api[_-]?key|secret|token|password)\s*[:=]\s*[\x27"][^\x27"]{12,}'`
      → CRITICAL; also check for committed `.env`.
- [ ] Client-exposed secrets: `rg -n 'NEXT_PUBLIC_|VITE_|PUBLIC_'` naming
      anything secret-like → CRITICAL.
- [ ] Secret comparison with `===`: `rg -n '(token|secret|signature|hmac)\s*===' `
      → HIGH (timing oracle).
- [ ] Error detail returned to clients: `rg -n 'res\.(json|send)\(.*\berr(or)?\b'`
      → MEDIUM (stack/SQL leakage).
- [ ] TLS disabled: `rg -n 'NODE_TLS_REJECT_UNAUTHORIZED|rejectUnauthorized:\s*false'`
      → CRITICAL in anything shipped.
- [ ] Lockfile absent, or CI installing unfrozen (`rules/01` checklist) → HIGH.
- [ ] Install scripts in the dependency tree unaudited, or CI running installs
      with scripts enabled and no allowlist → MEDIUM.
- [ ] No SCA/audit step in CI → MEDIUM; audit present but never triaged → LOW.
- [ ] ReDoS shapes: `rg -n '\(\[?[^)]*[+*]\)[+*]' --glob '**/*.ts'` and any regex
      built from user input without escaping → HIGH.
- [ ] Missing body/upload size limits on request parsing → MEDIUM.
- [ ] Regex built from input or validating only a substring:
      `rg -n 'new RegExp\(' --glob '**/*.ts'` with a non-literal argument and no
      `RegExp.escape`/escape helper → HIGH; then read each validation regex
      (`rg -n '\.test\(|\.match\(' --glob '**/*.ts'`) for missing `^`/`$`, or a
      trailing `/m` (`rg -n '/[a-z]*m[a-z]*\.test\('`) → MEDIUM, HIGH when it
      gates authorization, a redirect target, or a filename.
- [ ] Temp files: `rg -n "/tmp/|tmpdir\(\)|exists\(|existsSync\(" --glob '**/*.ts'`
      — fixed names under a shared directory, or `mkdtemp` absent where a temp
      file is written, or `writeFile` without `flag: 'wx'` after an exists
      check → MEDIUM, HIGH when the path is predictable and the content is
      sensitive or later executed.
- [ ] Secrets printed by value: read where config/env secrets are stored — a
      bare `string` in a config object that is later logged is a finding.
      `rg -n 'inspect\.custom|toJSON' --glob '**/*.ts'` finds existing
      wrappers; then `rg -n 'log\w*\.\w+\((err|error|e)\b|console\.\w+\((err|error|e)\b|JSON\.stringify\((err|error|config|options|req)\b'`
      for whole error/config/request objects reaching output → HIGH when the
      object can carry an `Authorization` header or token; also
      `rg -n '[?&](token|api[_-]?key|secret|password)='` → HIGH.
- [ ] Debug surface shipped: `rg -n -- '--inspect' Dockerfile* package.json docker-compose* .github/`
      with a host of `0.0.0.0` or a published port → CRITICAL; any `--inspect`
      in a production start script → HIGH; `rg -n "NODE_ENV|DEBUG" Dockerfile* .env*`
      for dev values in deploy config → MEDIUM; `rg -n 'sourcemap|--sourcemap'`
      in build config and `ls dist/**/*.map` in the deploy artifact → MEDIUM
      for browser bundles served publicly (maps expose source).
