# 02 — Privacy by Design Patterns

Privacy by design means the default behavior of the system — schemas, API
contracts, access paths, settings — protects the data subject without anyone
remembering to. For systematic privacy threat elicitation (linkability,
identifiability, non-repudiation, detectability, disclosure, unawareness,
non-compliance), use LINDDUN threat modeling; this file gives the
build patterns that those threats demand.

## 1. Data minimization — the field you don't store can't leak

**Rule:** Collect a field only when a named feature needs it now. Reject "might be
useful later," "the form library includes it," and "marketing asked." For every
proposed field, require: purpose, consumer (which code reads it), retention, and
deletion path. No answer = no field.

**Rationale:** Every stored PII field has permanent carrying cost: breach blast
radius, DSAR/export surface, deletion graph edge, transfer analysis, audit scope.
Minimization is the only privacy control with negative cost.

```text
GOOD: Signup form: email + password. Date of birth requested only when the user
enables the age-gated feature, with the gate as documented purpose.

BAD: Signup form: full name, DOB, phone, gender, company, job title — "for the
profile" — where the product uses only email. Six liabilities, zero features.
```

**Minimize in dimensions, not just fields:**
- **Precision:** store city, not GPS coordinates; year of birth, not full DOB;
  truncate IPs (/24, /48) when only geo/abuse-tier matters.
- **Duration:** event-level data → aggregate after N days, drop raw (rules/03 §6).
- **Population:** sample analytics (1-in-N users) instead of recording everyone.
- **Payloads in transit:** internal services pass user IDs, not embedded user
  objects; each consumer fetches only the fields it is purpose-scoped to read.

**API design corollary:** responses return the minimal projection per consumer.
A `GET /users/{id}` that returns 40 fields to every internal caller makes every
caller part of the PII surface. Use field masks / per-audience DTOs / GraphQL with
field-level authorization.

```typescript
// GOOD: explicit per-audience projections — adding a column to the table
// changes NO response until someone deliberately adds it to a DTO
const PublicProfile  = pick(User, ['id', 'displayName', 'avatarUrl']);
const SupportView    = pick(User, ['id', 'displayName', 'email', 'createdAt']);
const BillingView    = pick(User, ['id', 'email', 'countryCode']);

// BAD: res.json(user) — serializes the ORM entity; the day someone adds
// `internal_risk_score` or `date_of_birth` to the model, every consumer
// (and every consumer's logs) receives it. Disclosure by default.
```

## 2. Purpose limitation in code

**Rule:** Purpose is machine-readable metadata bound to data (rules/01 §1) AND an
access-control dimension. A service or job declares the purposes it serves; access
to purpose-tagged data outside a declared purpose is denied or at minimum audited.

```python
# GOOD: purpose is an explicit, logged dimension of data access
@requires_purpose("fraud_detection")           # declared in service manifest,
def get_payment_history(user_id, ctx):         # checked against field purpose tags,
    ...                                        # recorded in the access log

# BAD: any authenticated internal service reads any column; "purpose" exists only
# in the privacy policy. Marketing job quietly reads fraud-purpose device data —
# nothing stops it, nothing records it.
```

Pragmatic ladder (adopt the highest rung you can sustain):
1. Purpose tags in catalog + code review enforcement (minimum).
2. Separate credentials/roles per purpose-bound consumer; DB grants per
   view/column group using engine-native column/row-level controls.
3. Purpose claim in service-to-service auth tokens, enforced at the data API,
   producing per-purpose access logs (gold standard; also makes DSAR "who accessed
   my data and why" answerable).

**Repurposing is a change event:** using existing data for a new purpose (e.g.,
training an ML model on support tickets) requires a catalog purpose update,
compatibility/lawful-basis review, and possibly consent re-prompt — encode this as
a required review on purpose-tag diffs.

## 3. Pseudonymization, tokenization — and why most "anonymization" fails

**Definitions that matter legally and technically:**
- **Pseudonymized:** identifiers replaced, but a mapping (key, table, or feasible
  linkage) exists. Still personal data under GDPR (Recital 26). Valuable as a
  security measure; changes nothing about DSAR/deletion obligations.
- **Anonymized:** re-identification not reasonably likely by any party with any
  auxiliary data — only then does data leave GDPR scope. This bar is far higher
  than engineers assume.

**Common failures to flag on sight (each is a finding, not a nitpick):**

| Claim | Why it fails |
|---|---|
| "We hash the email (SHA-256), so it's anonymous" | Deterministic hash of a low-entropy identifier = trivially reversible by dictionary; also still linkable across datasets — it IS a pseudonymous ID |
| "We removed names and emails" | Quasi-identifiers remain: ZIP + birthdate + gender uniquely identifies most of a population; timestamps + location traces are fingerprints |
| "It's just internal user IDs" | Linkable to identity via any join; pseudonymous, not anonymous |
| "We aggregated it" | Small cells (count < k), max/min values, or repeated overlapping queries re-identify; differencing two aggregates isolates one person |

**k-anonymity basics (use as a floor, not a guarantee):** a release is k-anonymous
if every quasi-identifier combination matches ≥ k records. Enforce via
generalization (age → 5-year bands), suppression (drop rare combinations), and
minimum cell-size thresholds on any exported aggregate (k ≥ 10 is a common floor;
pick per risk). Know the limits: homogeneity (all k records share the sensitive
value) and auxiliary-data attacks still break it — which is why "anonymized"
requires a documented review with attack assumptions, not a checkbox.

**Tokenization:** replace the sensitive value with a random token; the vault
holding the mapping becomes the high-security zone, and downstream systems fall
out of sensitive scope. This is THE PCI DSS descoping move (rules/04 §5) and works
for SSNs/bank details too:

```text
GOOD: checkout posts card → tokenization service/PSP; app DB stores tok_8f3a...;
fraud, refunds, reporting all operate on tokens. PCI scope = the vault + capture
path, not your whole platform.

BAD: orders table stores PAN "for refund convenience" → entire DB, its backups,
its replicas, every service with DB access, and every admin laptop with a SQL
client are now in PCI scope.
```

Format-preserving encryption is a variant when downstream systems require the
original format; apply rigorous key lifecycle management.

**If you need a linkable pseudonym, build it honestly** — keyed, salted,
rotatable, scoped — not a bare hash:

```python
# GOOD: keyed pseudonymization — per-context key from KMS; unlinkable across
# contexts; rotating the key severs all linkage (a deletion lever)
def pseudonym(user_id: str, context: str) -> str:
    key = kms.get_key(f"pseudo/{context}")          # per-purpose key, access-logged
    return hmac_sha256(key, user_id).hex()[:32]

# BAD: sha256(email) — dictionary-reversible (emails are low-entropy),
# globally linkable (same input → same output everywhere, forever),
# irrevocable (no key to rotate or destroy). This is a tracking ID, not privacy.
```

Per-context keys give you compartmentalization (analytics pseudonyms can't join
against support pseudonyms) and a kill switch (destroy the context key →
pseudonyms in that context become unlinkable noise — crypto-shredding's cousin,
rules/03 §4).

## 4. Differential privacy & privacy-preserving analytics — when aggregates are exposed

**Rule:** If you expose statistics computed over personal data (public dashboards,
customer-facing benchmarks, partner data shares, published research), per-record
suppression is not enough — use differential privacy (calibrated noise with a
privacy budget) or strict k-thresholding with query auditing. DP is the only
approach with a formal guarantee against differencing attacks; mature libraries
(OpenDP, Google DP building blocks) make it practical for counts/sums/means.
Don't hand-roll noise mechanisms; budget composition is where amateurs leak.

```sql
-- GOOD: aggregate endpoint with k-threshold enforced in the view itself,
-- so no caller can extract small cells
CREATE VIEW public_usage_stats AS
SELECT region, plan, count(*) AS users, avg(events_30d) AS avg_activity
FROM   accounts GROUP BY region, plan
HAVING count(*) >= 10;            -- cells under k are suppressed, structurally

-- BAD: the dashboard API accepts arbitrary filters over raw events; an analyst
-- (or a partner with API access) filters to zip=94110 AND age=87 AND plan=pro
-- → cohort of one. Re-identification by query, no breach required.
```

**Decision ladder for analytics generally (prefer the earliest viable rung):**
1. Don't collect (feature flags + server metrics may answer the question).
2. Collect aggregates only, client-side or at ingestion (no event-level PII at rest).
3. Event-level, first-party, pseudonymous, short raw retention (e.g., 90 days →
   aggregate), no third-party sharing.
4. Third-party analytics: processor with DPA, EU-hostable if needed, IP truncation
   on, identify-calls minimal (rules/01 §4).
Session replay and heatmap tools deserve special suspicion: they exfiltrate form
contents and screens wholesale — require explicit masking allowlists, not blocklists.

## 5. Default-private settings

**Rule:** Every setting affecting personal-data exposure defaults to the most
private option (GDPR Art. 25 "data protection by default"). Visibility = private;
optional analytics/marketing = off until consent; discoverability (search by
email/phone) = opt-in; new fields excluded from existing exports/shares until
reviewed.

```text
GOOD: new "activity status" feature ships default-off with a consent-gated toggle.
BAD: profile photos default public "for engagement"; telemetry opt-out buried in
settings; new column auto-included in the partner data feed because the export
does SELECT *.
```

That last one is an architectural rule: **no `SELECT *` across trust boundaries.**
Exports, feeds, webhooks, and API responses enumerate fields explicitly so that
adding a column never silently widens disclosure.

## 6. LINDDUN threats → build patterns (quick map)

When a LINDDUN session raises a threat, these are the
default mitigations in this skill:

| LINDDUN threat | Primary mitigation here |
|---|---|
| Linkability | Per-context pseudonyms (§3), purpose-scoped access (§2), compartmentalized keys |
| Identifiability | Minimization/precision reduction (§1), k-threshold & DP on releases (§4) |
| Non-repudiation (user can't deny) | Minimize identity binding in records; aggregate where intent allows |
| Detectability (existence leaks) | Uniform responses/timing on lookup APIs; don't confirm account existence |
| Disclosure of information | Projections (§1), tier-bound encryption & access (rules/01 §2) |
| Unawareness | Notices + consent records at collection (rules/03 §1), default-private (§5) |
| Non-compliance | Catalog + CI gates (rules/01), retention automation (rules/03 §6) |

## 7. Retrofit order for existing systems (AUDIT → remediation)

When auditing a system that was not built this way, recommend remediation in this
order (highest risk-reduction per effort first):
1. Stop the bleeding: kill unpurposed collection, PII logging, `SELECT *` exports.
2. Tokenize/segregate the highest-tier data (cards, special-category) to shrink scope.
3. Add retention enforcement (rules/03 §6) — drains the historical pool.
4. Bind purpose/classification annotations + CI gate (rules/01) — stops regression.
5. Tighten access to purpose-scoped roles.
6. Re-evaluate claimed anonymization with §3's failure table.

## Audit checklist

- [ ] Every collected field traces to a named feature/purpose; sample 10 fields and demand the consumer code path
- [ ] Precision minimized where full precision is unused (GPS, full DOB, full IP)
- [ ] Internal APIs return minimal projections; no whole-user-object passing or `SELECT *` across trust boundaries
- [ ] Purpose tags exist and are enforced by at least code review; access roles segmented by purpose for high tiers
- [ ] New-purpose reuse of existing data triggers a documented review (check git history of purpose tags)
- [ ] No "anonymized" claim rests on hashing identifiers or removing direct identifiers only; quasi-identifier risk assessed, k-threshold on aggregate releases
- [ ] Cardholder/SSN-class data is tokenized or vaulted; verify no raw values in app DB, logs, or backups
- [ ] Public/partner-facing aggregates use DP or k ≥ threshold with documented rationale
- [ ] All privacy-affecting settings default private/off; check the three most recent features
- [ ] Session replay / heatmap tooling absent or mask-allowlisted and consent-gated
