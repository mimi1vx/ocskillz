# 06 - Performance

Optimize measured, production-like Haskell, not folklore about laziness or
strictness. Establish a baseline, profile the relevant resource, make one
behavior-preserving change, and repeat. Load `deep-performance-audit` for the
full measurement/equivalence workflow; this file covers Haskell-specific tools.

## 1. Define and preserve the baseline

State the metric before changing code: wall time, CPU, allocation, maximum
residency, p95/p99 latency, throughput, startup, binary size, or GC pause. Record
GHC version, optimization flags, dependency plan, machine, capabilities, RTS
options, input shape, and run count.

```bash
cabal build exe:service --enable-optimization=2
cabal run service -- +RTS -s -RTS
```

`+RTS -s` is the first diagnostic, not a complete profile. Compare allocated
bytes, copied bytes, maximum residency, productivity, and GC generation times.
High allocation with low residency suggests churn; high residency suggests
retention; low productivity can indicate GC pressure or poor parallel scaling.
External I/O and queueing require application metrics/traces as well.

Use identical inputs and force equivalent outputs. A faster program that does
less work because it leaves a lazy result unevaluated is not an optimization.
Never publish a benchmark claim without commands, environment, before/after
results, variance, and semantic validation.

## 2. Use the eventlog for runtime behavior

Build with eventlog support and collect a representative run:

```bash
cabal build exe:service --ghc-options='-eventlog'
cabal run service -- +RTS -l-au -N2 -RTS
```

Inspect the `.eventlog` with ThreadScope, eventlog2html, or ghc-events-analyze.
Select event classes deliberately; broad logging can produce large artifacts
and perturb timing.

Use the eventlog to answer:

- Are capabilities busy or idle?
- Are sparks created, converted, fizzled, or garbage-collected?
- Do stop-the-world GC pauses dominate latency?
- Is work balanced across capabilities?
- Are threads blocked on STM, `MVar`, or I/O?
- Does shutdown leave work alive?

Eventlogs may include user messages, identifiers, and timing-sensitive details.
Protect them like logs and expire them after analysis.

## 3. CPU cost-centre profiling

Use a profiling build for attribution, accepting that profiling changes
optimization, allocation, and inlining behavior:

```bash
cabal run exe:service --enable-executable-profiling \
  --enable-library-profiling --ghc-options='-fprof-auto' -- +RTS -p -RTS
```

Read inherited and individual time/allocation together. A broad caller may own
cost inherited from a small callee; call counts distinguish one expensive call
from millions of cheap ones.

- Prefer explicit `SCC` annotations or focused `-fprof-auto` after initial
  localization. Instrumenting everything can distort the result and generate
  noisy reports.
- Profile a long enough workload that startup and profiler overhead do not
  dominate, unless startup is the metric.
- Compare against non-profiled optimized runtime before claiming an absolute
  speed change.
- Native libraries, kernel waits, database execution, and network latency need
  their own profilers or traces; cost centres cannot explain them fully.

## 4. Heap profiling and retainer diagnosis

Select the heap view that matches the hypothesis:

```bash
# By producer cost-centre stack, sampled over time
cabal run exe:service --enable-executable-profiling \
  --enable-library-profiling -- +RTS -hc -p -RTS

# By closure description
cabal run exe:service --enable-executable-profiling \
  --enable-library-profiling -- +RTS -hd -RTS

hp2ps -c service.hp
```

Useful breakdowns include producer cost-centre stack (`-hc`), closure
description (`-hd`), type (`-hy`), retainer (`-hr`), and biography (`-hb`).
`-hcc` selects a particular cost centre rather than enabling general cost-centre
stack profiling. Confirm exact flags against the installed GHC users guide; RTS
profiling options and output naming vary by release.

- A heap profile shows live sampled heap, not all allocations. Combine it with
  `+RTS -s` and CPU/allocation profiles.
- Retainer profiling is expensive but answers why values remain reachable.
- Lower sample intervals increase detail and overhead.
- Heap profiles and core dumps can contain secrets or user data. Store them in
  restricted locations and remove them promptly.

## 5. Control strictness; do not maximize it

Laziness enables streaming and composition but can retain inputs or accumulate
thunks. Strictness can remove a space leak or destroy streaming and increase
peak residency. Change it only with evidence.

```haskell
-- BAD for a large list: accumulator becomes a chain of additions.
sumBad :: [Int] -> Int
sumBad = foldl (+) 0

-- GOOD: strict accumulator, same result for this finite workload.
sumGood :: [Int] -> Int
sumGood = foldl' (+) 0
```

Common retention hazards:

- lazy `foldl`, lazy state fields, and repeated lazy `modifyIORef`/`modifyTVar`;
- retaining the head of an input while producing or consuming its tail;
- closures capturing a large request/configuration graph;
- lazy I/O keeping handles and buffers alive beyond a visible scope;
- caches without capacity or expiry;
- `ByteString` slices retaining a large backing buffer;
- building lazy `Text`/`ByteString` output faster than it is consumed.

Use `foldl'`, strict fields (`!`), `BangPatterns`, `deepseq`, `evaluate`,
`modifyIORef'`, and `modifyTVar'` at proven boundaries. Weak-head normal form
only evaluates the outer constructor; `evaluate (length xs)` forces the spine,
not each element. `force`/`NFData` can do much more work than intended.

```haskell
-- BAD: strictness annotation only forces the Just constructor.
let !result = Just (expensive input)

-- GOOD when the benchmark/ownership boundary requires full evaluation.
result <- evaluate (force (Just (expensive input)))
```

## 6. Choose representations from access patterns

- `Data.Map` gives ordered keys and `O(log n)` operations; `HashMap` can improve
  lookup-heavy workloads but needs a suitable hash and carries collision/DoS
  considerations for attacker-controlled keys.
- `IntMap`/`IntSet` avoid general key comparison/hashing for integer keys.
- `Seq` supports efficient operations at both ends; lists are excellent for
  prepend and traversal, poor for indexing, repeated append, and length checks.
- `Vector` provides contiguous indexed storage and is the default candidate for
  dense numeric/bulk transforms. Prefer unboxed/storable vectors only when the
  element and FFI/layout requirements justify them.
- Strict `ByteString` is appropriate for bounded byte payloads; lazy
  `ByteString` is a chunked stream representation, not an automatic memory
  bound. Builders are usually preferable for large serialized output.
- `Text` represents Unicode text; `ByteString` represents bytes. Repeated
  encode/decode in a hot path is both a design smell and measurable cost.
- `ShortByteString` or compact text representations can reduce long-lived
  object overhead, but conversion may erase the gain.

```haskell
-- BAD: quadratic list append while constructing output.
build xs = foldl' (\acc x -> acc ++ render x) [] xs

-- GOOD: difference list/Builder-style composition, then materialize once.
build xs = foldMap renderBuilder xs
```

Measure end-to-end, including conversion, hashing, cache locality, and retained
memory. Do not replace a safe collision-resistant map strategy on hostile keys
solely for a microbenchmark.

## 7. Let fusion work, but verify it

`vector`, `text`, `bytestring`, and stream libraries can fuse producer/consumer
pipelines and remove intermediate allocations. Fusion depends on rewrite rules,
phase control, function visibility, and optimization settings.

- Prefer library combinators that participate in an established fusion system
  before writing hand loops.
- Avoid materializing intermediate lists/vectors with `toList`, `unpack`, or
  repeated conversions in hot pipelines.
- Polymorphism, wrappers, and module boundaries may prevent specialization or
  inlining. First prove allocation remains; then inspect simplifier output.
- `INLINE` duplicates code and can increase compile time and instruction-cache
  pressure. Use it for a small cross-module hot function only after a profile
  and benchmark. `INLINABLE` exposes a stable unfolding to downstream modules
  and also enlarges interface/build costs.
- Never depend on an undocumented rewrite rule for correctness. Test with and
  without optimization where relevant.

```haskell
-- BAD: conversions allocate and defeat a byte-oriented pipeline.
normalize = BS.pack . map transform . BS.unpack

-- GOOD: stay in the representation; benchmark/fusion-check the operation.
normalize = BS.map transform
```

## 8. Tune concurrency and GC from evidence

More capabilities are not free. Compare a small matrix such as `-N1`, `-N2`,
and the deployment CPU quota while recording throughput, tail latency,
allocation, copied bytes, residency, and GC pause.

```bash
cabal run service -- +RTS -N1 -s -RTS
cabal run service -- +RTS -N2 -s -RTS
cabal run service -- +RTS -N4 -A32m -s -RTS
```

- `-A` increases nursery size and can reduce minor-GC frequency at the cost of
  memory per capability and potentially different pause behavior. Do not copy
  a value from another service.
- `-H` is a heap-size suggestion, not a hard limit; `-M` sets a heap limit but
  does not cover all process memory and may terminate the program. Enforce
  deployment memory limits independently.
- Parallel GC can help large heaps and hurt small/latency-sensitive workloads.
  Review current GHC RTS flags and measure.
- Excess worker threads increase allocation, queues, context switching, and
  contention. Bound concurrency before tuning GC around an overload bug.
- Sparks need enough granularity to amortize scheduling. Eventlog spark counts
  and wall-clock scaling are required evidence.

Keep operational RTS defaults in Cabal or deployment configuration only after
testing under the actual CPU/memory quota. Preserve an override path for
incident response.

## 9. Benchmark with Criterion without measuring laziness

Criterion provides repeated statistical measurement, but it cannot repair a
wrong benchmark.

```haskell
import Criterion.Main

main :: IO ()
main = defaultMain
  [ env (pure representativeInput) $ \input ->
      bench "decode" $ nf decodeRecord input
  ]
```

- `whnf f x` evaluates only the result's outer constructor. It is correct for
  operations whose useful work reaches WHNF; otherwise it can benchmark thunk
  construction.
- `nf f x` requires `NFData` and forces the complete result. Confirm that full
  normal form matches real consumption rather than adding artificial work.
- Use `env`/`envWithCleanup` for setup outside the timed loop. Do not accidentally
  benchmark file creation, random input generation, or shared mutable state
  unless that is the target.
- Validate old/new outputs before timing. Avoid optimizer-eliminated constant
  work and ensure each iteration starts from equivalent state.
- Benchmark realistic sizes and adversarial shapes; asymptotic differences hide
  in tiny fixtures.
- Report distributions and confidence intervals. Shared CI is noisy; use
  dedicated runners, instruction-count tools, or conservative regression
  thresholds rather than gating on a single small percentage.

```haskell
-- BAD: whnf sees Just and may leave expensiveWork unevaluated.
bench "work" $ whnf (\x -> Just (expensiveWork x)) input

-- GOOD if production consumes the whole payload.
bench "work" $ nf (\x -> Just (expensiveWork x)) input
```

## 10. Inspect Core only after profiling

Core inspection is an escalation tool for a localized question: did a function
inline, specialize, fuse, unbox, or retain an unexpected dictionary/closure?

```bash
cabal build lib:core --ghc-options='-O2 -ddump-simpl -dsuppress-all -ddump-to-file'
cabal build lib:core --ghc-options='-O2 -ddump-rule-firings -ddump-to-file'
```

Use focused modules and preserve the exact GHC/options from the benchmark.
Readable Core still does not prove machine-code quality or end-to-end speed;
return to allocation and timing measurements. `inspection-testing` can enforce
important no-allocation/fusion properties, but such tests are compiler-version
sensitive and should protect only material regressions.

## 11. Performance changes must keep semantics

- Do not replace total checks with partial functions or `unsafeCoerce`.
- Do not make evaluation stricter if it changes termination, exception timing,
  streaming, or resource use outside the tested input.
- Do not trade bounded memory for throughput without an explicit operational
  budget.
- Do not cache without ownership, invalidation, capacity, and secret/tenant
  isolation.
- Do not add `INLINE`, `UNPACK`, custom FFI, or manual worker pools based on
  intuition. Require before/after evidence and remove experiments that lose.

## References

- https://downloads.haskell.org/ghc/latest/docs/users_guide/profiling.html
- https://downloads.haskell.org/ghc/latest/docs/users_guide/runtime_control.html
- https://hackage.haskell.org/package/criterion
- https://hackage.haskell.org/package/vector
- https://hackage.haskell.org/package/bytestring
- https://hackage.haskell.org/package/text
- https://hackage.haskell.org/package/inspection-testing

## Audit checklist

```bash
# Baseline/profiling evidence and runtime configuration
rg -n '(\+RTS|-s|-p|-hc|-hcc|-eventlog|-fprof|Criterion|benchmark|eventlog)' . --glob '*.{hs,lhs,cabal,project,yaml,yml,md}'
rg -n '(with-rtsopts|ghc-options).*-(N|A|H|M|I|qg)' --glob '*.{cabal,project}'

# Laziness, retention, and accidental materialization leads
rg -n '\bfoldl\b|modify(IORef|TVar)\b|unsafeInterleaveIO|hGetContents|lazy' --glob '*.{hs,lhs}'
rg -n '\b(toList|fromList|unpack|pack|encodeUtf8|decodeUtf8)\b|\+\+|BS\.concat|T\.concat' --glob '*.{hs,lhs}'
rg -n '\b(force|deepseq|rnf|evaluate|BangPatterns|StrictData|UNPACK)\b' --glob '*.{hs,lhs}'

# Data structures, parallelism, and potentially unbounded retention
rg -n '\b(Map|HashMap|IntMap|Seq|Vector|ByteString|Text|Builder|parList|rpar)\b' --glob '*.{hs,lhs}'
rg -n '(cache|memo|TQueue|Chan|mapConcurrently|forkIO|newIORef)' --glob '*.{hs,lhs}'

# Optimizer directives and escalation artifacts: demand benchmark justification
rg -n '(INLINE|INLINABLE|SPECIALI[ZS]E|RULES|UNPACK|ddump-simpl|ddump-rule-firings)' --glob '*.{hs,lhs,cabal,project}'

# Reproducible first-pass measurements; run with representative inputs
cabal build all --enable-optimization=2
cabal test all --test-show-details=direct
cabal bench all
```

Grep hits are leads, not performance findings. Establish hotness, scale,
retention/allocation behavior, equivalent outputs, and repeatable before/after
measurements before recommending strictness, representation, inlining, fusion,
parallelism, or RTS changes. No benchmark claim is valid without evidence.
