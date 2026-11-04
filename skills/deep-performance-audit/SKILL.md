---
name: deep-performance-audit
description: Measure-first performance audit of a codebase. Baselines a representative workload, profiles to find the real hotspots, proposes behavior-preserving (isomorphic) optimizations ranked by impact, confidence, and effort, and proves each one keeps outputs identical. Use for "performance audit", "optimize the codebase", "why is this slow", "find inefficiencies", latency/throughput/memory work.
---

# Deep Performance Audit

This skill is the canonical owner of measure-first performance methodology:
baselines, profiles, equivalence proofs, opportunity ranking, and regression
guardrails. Language and domain skills provide hotspot-specific techniques
(`sota-python`, `sota-rust`, `sota-typescript`, …); do not duplicate this
workflow from them.

## 0. Understand the system

Run `deep-project-primer` if you have not primed on this project in the current
session. You cannot judge what matters for latency or throughput without
knowing what the system does, how the pieces connect, and which paths are hot
in real use.

## 1. What qualifies

Only pursue changes that meet all three:

1. **Moves the needle** — measurably improves end-to-end latency,
   responsiveness, throughput, or peak memory for a realistic workload, not
   a micro-benchmark nobody runs.
2. **Provably isomorphic** — identical outputs for identical inputs
   (including ordering, error behavior, and side effects), so the change is
   safe by construction.
3. **Clearly better** — a better algorithm or data structure you can name and
   justify, not a hunch.

## 2. Methodology (do these in order)

- **A) Baseline first.** Run the test suite and a representative workload.
  Record p50/p95/p99 latency, throughput, and peak memory with the exact
  commands, inputs, machine, and number of runs. Repeat enough to know the
  noise floor.
- **B) Profile before proposing.** Capture CPU, allocation, and I/O profiles;
  name the top 3–5 hotspots by % of time or bytes. No proposal without a
  profile line that justifies it.
- **C) Equivalence oracle.** Define golden outputs and invariants (sorted
  order, totals, error cases) that any change must preserve; capture them from
  the baseline build.
- **D) Isomorphism proof per change.** Every proposed diff carries a short
  proof sketch of why outputs cannot change.
- **E) Opportunity matrix.** Rank candidates by `(Impact × Confidence) / Effort`
  before implementing anything; show the table.
- **F) Minimal diffs.** One performance lever per change, no unrelated
  refactors. Re-measure after each; revert anything inside the noise floor.
- **G) Regression guardrails.** Add a benchmark threshold, CI check, or
  monitoring hook so the gain cannot silently erode.

## 3. Patterns to look for

- N+1 query/fetch patterns → batching, joins, prefetch
- Linear scans where an index, hash map, or set lookup fits
- Repeated work → memoization (with a correct invalidation story),
  pre-computation, lookup tables
- Serialization and parse/encode overhead; needless copies → zero-copy,
  buffer reuse, scatter-gather I/O
- Unbounded buffering → streaming/chunked processing, bounded queues with
  backpressure
- Lock contention → sharding, striped locks, lock-free reads
- Eager work whose result is often unused → lazy/deferred evaluation
- Algorithmic: dynamic programming, binary search (on data and on the answer
  space), two pointers / sliding window, prefix sums

## 4. Report

1. Baseline table (commands, metrics, noise floor).
2. Hotspots with profile evidence.
3. Opportunity matrix.
4. Per implemented change: diff summary, isomorphism proof, before/after
   numbers, guardrail added.
5. Rejected or deferred candidates, with the reason.

Do not implement beyond the analysis without the user's go-ahead when the
change set is large or touches public behavior.
