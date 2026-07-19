# 06 - Performance

Optimize measured production-like work, not Perl folklore. Load
`deep-performance-audit` for a full baseline/profile/equivalence workflow; this
file supplies Perl-specific mechanics.

## 1. Profile with NYTProf

Profile representative inputs and runtime configuration:

```bash
NYTPROF=start=begin:addpid=1 perl -d:NYTProf app.pl
nytprofhtml --open
```

For forked workloads, use PID-separated files and merge them:

```bash
NYTPROF=addpid=1 perl -d:NYTProf app.pl
nytprofmerge --out nytprof-merged.out nytprof.out.*
nytprofhtml --file nytprof-merged.out
```

Read inclusive/exclusive subroutine time, call count, caller location, line
time, and slow opcodes together. `start=begin` includes compile/initialization
work; compare with `start=init` to exclude it when startup matters. NYTProf has
thread and embedded-runtime limitations; document the measurement environment
and profiler overhead.

Never profile production secrets into an unprotected artifact.

## 2. Separate Perl CPU from external latency

NYTProf cannot explain database execution plans, lock waits, network latency,
remote throttling, DNS, filesystem stalls, or queue time by itself.

- Instrument DB query count/duration and inspect query plans.
- Measure service/network spans and connection-pool wait separately.
- Distinguish CPU time, wall time, allocation, startup, and throughput goals.
- Reproduce concurrency and realistic data size; small synthetic inputs hide
  algorithmic and serialization costs.

## 3. Benchmark equivalent alternatives

Use coderefs and run long enough for stable comparison:

```perl
use Benchmark qw(cmpthese);

cmpthese(-5, {
    old => sub { old_impl() },
    new => sub { new_impl() },
});
```

- Validate outputs before timing.
- Warm caches deliberately or measure cold start deliberately; do not mix them.
- Report distribution/variance and environment for serious claims.
- Shared CI is unsuitable for small percentage gates. Use dedicated runners or
  trend reporting for regressions with practical thresholds.
- Do not benchmark string eval forms against coderefs; compilation contaminates
  results.

## 4. Algorithm and data shape first

- Replace repeated linear membership scans with a hash/set.
- Avoid nested passes when one indexed pass suffices.
- Stream large inputs instead of slurping when whole-document semantics are not
  required.
- Avoid accidental list materialization (`map`, `grep`, ranges, `keys`) on
  unbounded data.
- Batch DB work and eliminate N+1 queries before optimizing scalar operations.
- Choose serialization and schema based on measured size/CPU and interoperability,
  not benchmark headlines detached from the workload.

## 5. Strings, copies, and references

Perl copy-on-write reduces some string-copy cost, but modification can trigger a
real copy. References avoid structural flattening but introduce ownership and
lifetime concerns.

- Build large output with `join`, a handle, or bounded buffers rather than
  repeated concatenation if the profiler identifies it.
- Pass references for large structured values and document mutation/retention.
- Avoid deep cloning by default; clone only at an ownership boundary.
- Do not retain large request graphs in closures, caches, futures, or global
  diagnostics after work completes.
- Preallocation and low-level buffer tricks require measured benefit and clear
  invariants.

## 6. Regex performance

- Precompile truly reusable dynamic patterns with `qr//`; constant patterns are
  already compiled efficiently.
- Avoid recompiling patterns containing changing interpolation in hot loops.
- Anchor and constrain patterns to reduce search/backtracking.
- Catastrophic backtracking is a security/correctness defect, not merely a slow
  implementation; see rules/05.
- Prefer parsers or indexed string operations when regex complexity obscures a
  linear grammar.

## 7. DBI and I/O throughput

- Prepare once and execute many where driver semantics permit.
- Use transactions for batches; autocommit per row is often dominated by
  durability round trips.
- Fetch only required columns/rows and select an appropriate fetch API.
- Bound connection pools and concurrency; more parallel queries can reduce
  throughput through contention.
- Use buffered vs streaming fetch deliberately and observe memory.
- Do not replace safe placeholders or transaction checks for speed.

## 8. Startup and module loading

For CLIs, serverless jobs, and short-lived workers, compile/module load can
dominate.

- Profile with and without `start=init` to separate startup and runtime.
- Load heavy optional dependencies only inside the feature boundary.
- Avoid expensive `BEGIN`, import, and global initialization work.
- Do not broadly delay required modules if it makes runtime errors or packaging
  metadata inaccurate.
- Persistent workers trade startup for memory/staleness; add recycle policy and
  measure steady-state behavior.

## 9. Memory diagnosis

Use the right tool for the question:

```bash
perl -MDevel::MAT::Dumper=-dump_at_END,-file,heap.pmat app.pl
pmat heap.pmat
```

- Devel::MAT snapshots help identify retained graphs and leaks across equivalent
  workload checkpoints.
- Devel::Size estimates a Perl data structure but omits allocator fragmentation,
  alignment, C-library/XS state, and some interpreter internals.
- Observe RSS/PSS and worker growth in the deployment environment.
- Heap/profile dumps contain application data and secrets; protect and expire
  them.
- Fork copy-on-write savings disappear as parent/child mutate pages; preload
  only when measurements prove benefit.

## 10. XS and alternate runtimes

XS can improve hot numeric/parsing loops but adds memory-safety, ABI, build,
platform, and supply-chain risk.

- Exhaust algorithm, batching, maintained modules, and architecture changes
  before writing custom XS.
- Benchmark end-to-end including conversion/call overhead.
- Add sanitizers, fuzzing, platform/Perl matrix tests, and strict length/overflow
  checks for XS.
- Do not depend on undocumented interpreter internals.
- A pure-Perl fallback may be valuable for portability; test both paths for
  identical semantics.

## Audit checklist

```bash
# Existing performance evidence and tooling
rg -n 'NYTProf|Benchmark|Devel::(MAT|Size|Cover)|nytprof|benchmark' . --glob '!local/**'

# Likely algorithm/materialization leads; inspect hotness before findings
rg -n 'for(each)?\s+.*\{[^}]*for(each)?|grep\s+.*@|map\s+.*@|\b(0\s*\.\.\s*\$#|keys\s+%)' --glob '*.{pl,pm,t}'
rg -n '\.=|join\s*\(|slurp|read_file|local\s+\$/|<[^>]+>' --glob '*.{pl,pm,t}'

# Database and I/O shape
rg -n '->(prepare|execute|do|select\w*|fetch\w*)\b|AutoCommit|begin_work|commit|rollback' --glob '*.{pl,pm,t}'
rg -n 'select \*|SELECT \*' --glob '*.{pl,pm,t,sql}'

# Caches, globals, closures, and unbounded retention
rg -n '\bstate\b|our\s+[%@]|cache|memo|closure|Future->new|Mojo::Promise' --glob '*.{pl,pm,t}'

# Regex compilation/hot dynamic patterns
rg -n '=~\s*m?.*\$|qr[/({].*\$|s[/({].*\$' --glob '*.{pl,pm,t}'

# XS/native scope
ls *.xs typemap 2>/dev/null
rg -n 'XSLoader|DynaLoader|Inline::|FFI::Platypus' --glob '*.{pl,pm,xs}' cpanfile
```

No grep hit is a performance finding without profile evidence, scale, and a
behavior-preserving alternative.

## References

- https://metacpan.org/pod/Devel::NYTProf
- https://perldoc.perl.org/Benchmark
- https://metacpan.org/pod/Devel::MAT
- https://metacpan.org/pod/Devel::Size
- https://metacpan.org/pod/DBI
