---
name: deep-performance-audit
description: Hyper-intensively investigate and study the codebase to identify gross inefficiencies, propose isomorphic performance improvements, and strictly follow a methodology of baselining, profiling, and proving equivalence.
---

# Deep Performance Audit

This skill is the canonical owner of measure-first performance methodology:
baselines, profiles, equivalence proofs, opportunity ranking, and regression
guardrails. Language and domain skills provide hotspot-specific techniques;
do not duplicate this workflow from them.

First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Then, once you've done an extremely thorough and meticulous job at all that and deeply understood the entire existing system and what it does, its purpose, and how it is implemented and how all the pieces connect with each other, I need you to hyper-intensively investigate and study and ruminate on these questions as they pertain to this project: are there any other gross inefficiencies in the core system? places in the codebase where 1) changes would actually move the needle in terms of overall latency/responsiveness and throughput; 2) such that our changes would be provably isomorphic in terms of functionality so that we would know for sure that it wouldn't change the resulting outputs given the same inputs; 3) where you have a clear vision to an obviously better approach in terms of algorithms or data structures.

Consider these optimization patterns:
- N+1 query/fetch pattern elimination
- zero-copy / buffer reuse / scatter-gather I/O
- serialization format costs (parse/encode overhead)
- bounded queues + backpressure
- sharding / striped locks to reduce contention
- memoization with cache invalidation strategies
- dynamic programming techniques
- lazy evaluation / deferred computation
- streaming/chunked processing for memory-bounded work
- pre-computation and lookup tables
- index-based lookup vs linear scan recognition
- binary search (on data and on answer space)
- two-pointer and sliding window techniques
- prefix sums / cumulative aggregates

METHODOLOGY REQUIREMENTS:
A) Baseline first: Run the test suite and a representative workload; record p50/p95/p99 latency, throughput, and peak memory with exact commands.
B) Profile before proposing: Capture CPU + allocation + I/O profiles; identify the top 3-5 hotspots by % time before suggesting changes.
C) Equivalence oracle: Define explicit golden outputs + invariants.
D) Isomorphism proof per change: Every proposed diff must include a short proof sketch explaining why outputs cannot change.
E) Opportunity matrix: Rank candidates by (Impact x Confidence) / Effort before implementing.
F) Minimal diffs: One performance lever per change. No unrelated refactors.
G) Regression guardrails: Add benchmark thresholds or monitoring hooks.
