# 04 — Async & Concurrency

JavaScript is single-threaded with a cooperative event loop. Nothing preempts
your code, so the failure modes are not data races — they are **dropped work,
unbounded work, and work that never finishes**.

Cross-runtime design and the audit bug catalog live in `sota-async-concurrency`.

## 4.1 No floating promises

An un-awaited promise is a piece of work nobody owns. Its result is discarded,
its rejection escapes the surrounding `try`, and its timing is unrelated to the
code that started it.

```ts
// BAD — the request returns before the write lands; a failure crashes the
// process later, from a stack that no longer mentions this handler
app.post("/orders", async (c) => {
  saveOrder(order);
  return c.json({ ok: true });
});

// GOOD — awaited, so failures are this handler's problem
app.post("/orders", async (c) => {
  await saveOrder(order);
  return c.json({ ok: true });
});
```

If work is *deliberately* not awaited, say so and handle its failure:

```ts
void metrics.record(event).catch((err) => log.warn({ err }, "metrics failed"));
```

- **An unhandled rejection terminates the Node process by default.** Treat it
  as a crash, not a warning. A process-level `unhandledRejection` handler is
  for logging and orderly shutdown — never for swallowing.
- Background work that must survive the response needs a real mechanism (queue,
  outbox, task runner), not a floating promise. Serverless runtimes freeze the
  process after the response and the work simply never happens.
- Enable the linter's floating-promise rule. This is the highest-yield async
  lint that exists.

## 4.2 Concurrency combinators

Sequential `await` in a loop is the most common accidental performance bug in
TypeScript (`rules/06`). But unbounded parallelism is worse — it converts one
slow request into a thundering herd against your database.

```ts
// BAD — N round trips, one at a time
for (const id of ids) results.push(await fetchOne(id));

// BAD — N simultaneous connections; fine for 5 ids, an outage for 50,000
const results = await Promise.all(ids.map(fetchOne));

// GOOD — bounded fan-out
const results = await mapWithConcurrency(ids, 10, fetchOne);
```

| Combinator | Semantics | Use for |
|---|---|---|
| `Promise.all` | rejects on first failure; **other work keeps running unobserved** | small, known-size batches where any failure is fatal |
| `Promise.allSettled` | never rejects; returns per-item status | batch jobs where partial success is meaningful |
| `Promise.race` | settles with the first settled promise, success or failure | timeouts, first-response-wins |
| `Promise.any` | first *fulfilled*; rejects with `AggregateError` if all fail | redundant sources |

- **`Promise.all` does not cancel the losers.** After it rejects, the remaining
  requests still complete, still consume connections, and their rejections are
  unhandled unless you attached handlers. Pair it with an `AbortController`
  (§4.3) when the work is cancellable.
- **Bound every fan-out whose width comes from data.** A concurrency limit is a
  required parameter, not a tuning detail.
- `Promise.withResolvers()` replaces the deferred-promise boilerplate where you
  genuinely need to resolve from outside.

## 4.3 Cancellation: `AbortSignal` end to end

Every operation that can outlive its caller's interest needs a cancellation
path. `AbortSignal` is the platform's standard, understood by `fetch`, streams,
event listeners, and most modern libraries.

```ts
async function fetchOrder(id: string, signal?: AbortSignal): Promise<Order> {
  const res = await fetch(`${base}/orders/${id}`, {
    signal: AbortSignal.any([                    // caller's intent AND our SLA
      ...(signal ? [signal] : []),
      AbortSignal.timeout(2_000),
    ]),
  });
  if (!res.ok) throw new UpstreamError(res.status);
  return OrderSchema.parse(await res.json());
}
```

- **Accept a signal, propagate a signal.** A function that takes `signal` and
  does not pass it to its own awaits is lying about being cancellable.
- **`AbortSignal.timeout(ms)`** is the built-in deadline; **`AbortSignal.any`**
  composes several. Prefer them to hand-rolled `Promise.race` with a `setTimeout`
  — the race pattern leaves the timer and the losing operation running.
- **Cancellation surfaces as a rejection** (`AbortError`). Distinguish it from a
  real failure: an aborted request is usually not an error worth alerting on.
- Long CPU-bound or streaming loops must check `signal.aborted` between chunks;
  nothing interrupts synchronous code for you.
- On shutdown, abort the root controller, then await in-flight work with a
  bounded grace period (§4.7).

## 4.4 Timeouts are mandatory on external I/O

Any await that crosses the process boundary — HTTP, database, cache, queue,
subprocess, filesystem on a network mount — needs a deadline. Without one, a
hung dependency converts into an exhausted connection pool and a dead service.

- `fetch` has **no default timeout**. Neither do most database drivers'
  *query* paths, even when they have a connection timeout. Set both.
- Timeouts belong in the client wrapper, not sprinkled per call site, so the
  default cannot be forgotten.
- Budget them: an inner timeout must be shorter than the outer request's
  deadline, or the outer caller gives up while you keep working.
- Retry only idempotent operations, with jittered backoff and a cap. A retry
  without idempotency is a duplicate-charge bug; a retry without jitter is a
  synchronized stampede.

## 4.5 Don't block the event loop

One synchronous CPU burst stalls *every* concurrent request in the process,
including health checks.

- Common offenders: `JSON.parse`/`stringify` on multi-megabyte payloads,
  synchronous `crypto` key derivation and hashing, `fs.*Sync` outside startup,
  large `Array.sort`, regexes with catastrophic backtracking (`rules/05`), and
  template rendering of huge collections.
- Fix by: streaming instead of buffering (§4.6), chunking with a yield between
  batches, moving the work to a worker (§4.7), or pushing it out of the request
  path entirely.
- `fs.readFileSync` at module load is fine — that is startup, and it happens
  once. The same call inside a handler is a defect.
- Measure before assuming: `rules/06` owns profiling.

## 4.6 Streams and backpressure

Reading a whole response, file, or query result into memory works until the
input is large enough to matter, then it fails as an out-of-memory crash under
load rather than a clean error.

- Prefer **Web Streams** (`ReadableStream`, `TransformStream`, `Response.body`)
  — they are the cross-runtime standard and are what `fetch` gives you.
- **Respect backpressure.** Piping honors it; a manual read loop that pushes
  into an unbounded array or queue does not. If your consumer is slower than
  your producer and nothing pushes back, memory is your queue.
- Async iteration (`for await (const chunk of stream)`) is the readable default
  and propagates errors correctly — but note that `break`ing out must cancel
  the stream, or the underlying resource leaks.
- Never buffer an untrusted upload to compute its size; enforce a limit while
  streaming (`rules/05`).

## 4.7 Workers, parallelism, and shutdown

- **Workers for CPU, not for I/O.** I/O is already concurrent on one thread.
  Worker threads earn their keep for parsing, compression, image work, and
  crypto — anything that would block §4.5.
- Message passing copies (or transfers) data; passing large objects across the
  boundary can cost more than the computation saved. Transfer `ArrayBuffer`s
  rather than copying them.
- **Graceful shutdown** on `SIGTERM`: stop accepting new work, abort the root
  `AbortController`, await in-flight requests up to a grace period, close pools
  and flush telemetry, then exit. A service that exits immediately on `SIGTERM`
  drops in-flight requests on every deploy.
- Keep the grace period shorter than the orchestrator's kill timeout, or the
  platform `SIGKILL`s you mid-flush.

## 4.8 Async correctness details

- **`async` functions never throw synchronously** — they return a rejected
  promise. `try { doAsync() } catch {}` without `await` catches nothing.
- **`forEach` does not await.** `arr.forEach(async x => await f(x))` starts
  everything at once and returns immediately. Use `for...of` with `await`, or
  an explicit bounded map (§4.2).
- **`await` in a `finally` can swallow the in-flight rejection** if it throws;
  keep cleanup non-throwing, or prefer `await using` (`rules/03` §3.10).
- **Sequential awaits on independent work are pure latency.** Start both, then
  await both.
- Node's `AsyncLocalStorage` is the correct way to carry request context
  (trace id, tenant) across awaits — never a module-level mutable variable,
  which will bleed between concurrent requests.
- Do not mix callback and promise styles in one API; wrap callbacks once at the
  boundary (`node:util.promisify` or a hand-written adapter).

## Audit checklist

- [ ] Floating promises: is the linter's no-floating-promises rule enabled?
      Absent → HIGH (the whole class is invisible). Then spot-check:
      `rg -n '^\s+[a-zA-Z_$][\w.$]*\([^)]*\);\s*$' --glob '**/*.ts'` in async
      functions for un-awaited calls returning promises.
- [ ] `forEach` with an async callback:
      `rg -n '\.forEach\(\s*async' --glob '**/*.ts'` → HIGH (work is dropped).
- [ ] Unbounded fan-out from data:
      `rg -n 'Promise\.all\(\s*\w+\.map\(' --glob '**/*.ts'` → MEDIUM, HIGH when
      the array size is request- or database-driven.
- [ ] Sequential awaits in a loop:
      `rg -n -B3 'await ' --glob '**/*.ts' | rg -n 'for \(|while \('` → MEDIUM
      where the iterations are independent (`rules/06`).
- [ ] `fetch` without a timeout or signal:
      `rg -n 'fetch\(' --glob '**/*.ts'` and check for `signal:` → HIGH on
      server-side calls.
- [ ] Hand-rolled timeout races: `rg -n 'Promise\.race\(' -A3 | rg 'setTimeout'`
      → MEDIUM (timer and loser keep running; use `AbortSignal.timeout`).
- [ ] Signals accepted but not propagated:
      `rg -n 'signal[?]?: AbortSignal' -A15 --glob '**/*.ts'` where no inner call
      receives it → MEDIUM (falsely advertised cancellation).
- [ ] Retries without idempotency or jitter:
      `rg -n 'retr(y|ies)|backoff' --glob '**/*.ts'` on non-idempotent verbs
      → HIGH (duplicate side effects).
- [ ] Sync I/O or heavy crypto in a request path:
      `rg -n 'readFileSync|writeFileSync|execSync|pbkdf2Sync|scryptSync' src/`
      outside startup → HIGH.
- [ ] Whole-body buffering of untrusted input:
      `rg -n 'await (res|response|req|request)\.(text|json|arrayBuffer)\(\)'`
      without a size limit → MEDIUM, HIGH for uploads.
- [ ] Unhandled-rejection handler used to swallow:
      `rg -n "on\('unhandledRejection'" -A5` that neither logs nor exits → HIGH.
- [ ] No graceful shutdown: `rg -n "SIGTERM" src/` absent in a long-running
      service → MEDIUM (dropped requests on every deploy).
- [ ] Request context in module-level mutable state instead of
      `AsyncLocalStorage`: `rg -n '^(let|var) (current|active|request)' src/`
      → HIGH (cross-request bleed).
- [ ] `try` around an un-awaited async call:
      `rg -n -A3 'try \{' --glob '**/*.ts' | rg -n '^\s+\w+\([^)]*\);'` → MEDIUM.
