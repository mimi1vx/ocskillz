# 02 - Types and API Design

Use types to make invalid states difficult to construct and public contracts
easy to discover. Types do not replace runtime validation, authorization, or
resource limits; they preserve facts only after those facts enter through a
checked boundary.

## 1. Model alternatives with algebraic data types

Prefer one sum type over booleans, magic strings, or records whose fields are
valid only in certain combinations:

```haskell
-- BAD: paid=False with a receipt is representable; currency is unchecked.
data Payment = Payment
  { paid :: Bool
  , receipt :: Maybe Text
  , amount :: Integer
  , currency :: Text
  }

-- GOOD: each constructor carries exactly the data that state needs.
data Payment
  = Pending Money
  | Settled Money ReceiptId
  | Refunded Money ReceiptId RefundId
```

- Use a sum for alternatives and a product for facts that coexist.
- Give constructors domain names. A tuple or `Either Text Bool` forces callers
  to remember conventions that the compiler cannot explain.
- Do not encode every workflow transition at the type level. Start with an ADT;
  add phantom states or GADTs only when they prevent material misuse without
  making persistence, testing, and error reporting opaque.
- Keep wire/database representations separate from validated domain types.
  Decode, validate, then construct the domain value.

## 2. Use newtypes for meaning and boundaries

`newtype` distinguishes values with the same representation at no runtime cost
in ordinary optimized code:

```haskell
newtype UserId = UserId UUID
  deriving stock (Eq, Ord, Show)

newtype EmailAddress = EmailAddress Text
  deriving stock (Eq, Ord)

mkEmailAddress :: Text -> Either EmailError EmailAddress
mkEmailAddress input
  | validEmail input = Right (EmailAddress input)
  | otherwise = Left (InvalidEmail input)
```

Hide a constructor when construction must preserve an invariant. Export a smart
constructor and intentional observers. A hidden constructor is ineffective if
`Read`, generic decoding, coercion, or another exported function bypasses the
same validation.

- Do not use type synonyms for distinct domain identities: `type UserId = UUID`
  cannot prevent swapping a user and order identifier.
- Avoid deriving numeric classes for identifiers. `UserId + 1` is usually not a
  meaningful domain operation.
- Derive `Show` only when output is safe and useful; secret-bearing and personal
  data types need redacted rendering.
- A smart constructor validates local shape. Checks requiring a database,
  permission, or current time remain effectful boundary operations.

## 3. Make public functions total over their declared domain

A function is not total merely because it returns a non-`Maybe` value. Account
for empty inputs, failed parsing, overflow policy, nontermination, and exceptions.

```haskell
-- BAD: crashes on an empty collection.
primary :: [Account] -> Account
primary = head

-- GOOD: absence is part of the result.
primary :: NonEmpty Account -> Account
primary = NE.head

lookupAccount :: AccountId -> Map AccountId Account -> Maybe Account
lookupAccount = Map.lookup
```

- Strengthen the input type when absence is impossible by construction, such as
  `NonEmpty`; otherwise return `Maybe` or a domain-specific `Either`.
- Avoid `head`, `tail`, `init`, `last`, `!!`, `read`, `fromJust`, incomplete
  patterns, and `error` in exported or input-reachable code.
- Do not hide partiality under `HasCallStack`. Better diagnostics do not turn a
  process crash into a modeled result.
- Document unavoidable partial functions with their precondition and keep them
  internal behind a checked total API.

## 4. Design a small explicit module surface

Export lists are API design and abstraction enforcement:

```haskell
module Billing.Invoice
  ( Invoice
  , InvoiceId
  , InvoiceError (..)
  , createInvoice
  , invoiceId
  , invoiceTotal
  ) where
```

- Avoid `module X where` for public modules. An explicit list prevents helper,
  constructor, and imported-name leakage during refactoring.
- Export abstract types without `(..)` when constructors carry invariants.
- Export error constructors when callers are expected to branch on them; keep
  them abstract when only rendering or logging is supported and evolution is
  more important than exhaustive matching.
- Prefer qualified imports for modules with broad/common vocabularies. Use
  explicit imports where dependency and name provenance matter.
- Avoid deep re-export modules that make ownership, Haddock location, and
  versioning unclear. A deliberate package facade is acceptable when stable.
- Treat exposed modules, constructors, instances, field selectors, and class
  methods as compatibility commitments.

## 5. Keep records evolvable and unambiguous

Record fields are functions and may become public API. Prefer domain-specific
names where selector collisions or broad exports would be confusing. Preserve
existing project style for `DuplicateRecordFields`, `OverloadedRecordDot`, and
`NoFieldSelectors`; do not introduce an extension only to imitate another
language's syntax.

- Avoid records containing several `Maybe` fields whose valid combinations need
  prose. Split states into constructors.
- Do not expose update syntax for invariant-bearing records; hidden constructors
  plus named updates can revalidate changes.
- Adding a field breaks positional construction and exhaustive record patterns,
  even when consumers ignore the new data. Plan public record evolution.
- Strict fields are evaluation decisions, not merely style. Choose them from
  ownership and performance needs and document observable strictness where API
  behavior can change.

## 6. Add type classes only for real shared laws

Use a class when multiple types implement one coherent abstraction with laws
that generic callers can rely on:

```haskell
class Render a where
  render :: a -> Text

-- Prefer a normal argument for one strategy used in one subsystem.
writeReport :: (Report -> Text) -> Report -> IO ()
```

- A one-instance class is usually an indirect function or record of operations.
  Introduce it only for a credible open extension point or required effect API.
- Keep classes small. Methods should mention the class parameter enough to make
  instance selection and inference unsurprising.
- State laws in Haddock and test instances. `Eq`, `Ord`, `Semigroup`, `Monoid`,
  `Functor`, `Applicative`, and `Monad` carry semantic expectations beyond types.
- Avoid overlapping, incoherent, or undecidable instance machinery unless a
  localized design has no simpler representation and inference is tested.
- Prefer `newtype` to select alternate lawful behavior rather than orphan or
  overlapping instances.
- Functional dependencies, associated types, and type families are useful when
  they improve inference or express a real relation; do not add them preemptively.

## 7. Derive instances deliberately

Group deriving strategies so representation and intent are visible:

```haskell
newtype CustomerId = CustomerId UUID
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (Hashable)

data Direction = North | East | South | West
  deriving stock (Eq, Ord, Show, Enum, Bounded)
```

- `deriving stock` uses datatype structure; `deriving newtype` reuses the
  representation's instance; `deriving anyclass` fills class defaults and is
  easy to select accidentally. Use explicit strategies when ambiguity exists.
- Review semantic compatibility before newtype deriving `Num`, `Monoid`, JSON,
  persistence, or security-sensitive classes.
- Generic serialization couples the wire format to constructor and field names.
  Define explicit encoders/decoders for durable or external formats.
- Derived `Ord` follows constructor declaration order and field order. Do not use
  it as durable business priority unless that ordering is the documented contract.
- Derived `Enum` is partial outside constructor bounds and unstable when
  constructors move. Do not use it as a persistent numeric protocol.
- Avoid standalone deriving that defeats a module's abstraction boundary.

## 8. Understand roles and Coercible

GHC assigns type parameters nominal, representational, or phantom roles.
`coerce` is safe only when the required `Coercible` relation exists, but an
incorrectly permissive role can break an abstraction such as a validated,
type-indexed container.

```haskell
newtype UserSet a = UserSet (Set a)
type role UserSet nominal
```

- Use role annotations when a parameter's semantic identity matters more than
  its runtime representation, especially around type families or invariants.
- Do not use `unsafeCoerce` to bypass a failed role check. The failure often
  identifies a real abstraction boundary.
- Exported newtype constructors can permit coercion paths that smart constructors
  were meant to control. Review constructor exports and role inference together.
- Treat changing a public role annotation or representation as an API change;
  downstream `coerce` use may compile or fail differently.

## 9. Use language extensions with local purpose

Prefer the project's established baseline. For greenfield work on current GHC,
use `GHC2024` plus a short list of explicit extensions; use `GHC2021` or
individual extensions when the supported compiler floor requires it. Enable
extensions in the narrowest sensible scope and understand generated constraints,
instances, and desugaring.

- Do not enable `PartialTypeSignatures` to silence unfinished public types.
- Use `ScopedTypeVariables`, `TypeApplications`, GADTs, data kinds, and type
  families when they make a checked invariant or inference problem clearer.
- Treat `OverloadedStrings`, `OverloadedLists`, and numeric defaulting carefully
  at ambiguous boundaries; add type annotations where meaning matters.
- `Strict` and `StrictData` alter evaluation across a module. Do not enable them
  as blanket performance fixes.
- Template Haskell and plugins execute during compilation and enlarge the build
  trust boundary. Require a concrete benefit and review generated API.
- Avoid CPP for compiler-version branching where Cabal constraints or a
  compatibility module can express the same policy more clearly.

## 10. Keep orphan instances out of ordinary design

An orphan instance is defined in a module containing neither the class nor the
type. It can cause duplicate-instance failures and makes behavior depend on
which modules happen to be imported.

- Put the instance with the class or type when you own one of them.
- Otherwise wrap the external type in a local `newtype` and define the instance
  for that wrapper.
- Preserve a necessary existing orphan in a clearly named, explicitly imported
  module; document uniqueness and package-level coordination.
- Never suppress `-Worphans` globally to normalize accidental instances.

## 11. Document contracts with Haddock

Haddock public types and functions with semantics the signature cannot express:
units, ordering, validation, complexity, strictness, resource ownership,
thread-safety, exceptions, and examples.

```haskell
-- | Parse a bounded decimal amount.
--
-- Returns 'AmountOutOfRange' rather than wrapping. Leading @+@ is rejected.
parseAmount :: Text -> Either AmountError Amount
```

- Document class laws and whether instances must preserve them.
- Document which exceptions an `IO` action intentionally throws and who owns
  returned resources. Prefer typed ordinary failures over long exception lists.
- Keep examples deterministic and compilable through an established doctest
  workflow where practical.
- Run `cabal haddock all --haddock-all`; broken links and missing modules are API
  defects, not cosmetic warnings.

## References

- https://downloads.haskell.org/ghc/latest/docs/users_guide/exts.html
- https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/roles.html
- https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/deriving.html
- https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/orphan_modules.html
- https://www.haskell.org/onlinereport/haskell2010/haskellch5.html
- https://haskell-haddock.readthedocs.io/
- https://hackage.haskell.org/package/base/docs/Data-Coerce.html
- https://hackage.haskell.org/package/base/docs/Data-List-NonEmpty.html

## Audit checklist

```bash
# Public surfaces, broad exports, constructors, records, and re-exports
rg -n '^module .* where$|^module .*[([]|module [A-Z][A-Za-z0-9_.]+,' --glob '*.{hs,lhs}'
rg -n 'exposed-modules:|data |newtype |type |class |instance ' --glob '*.{cabal,hs,lhs}'

# Partial APIs and hidden crash paths
rg -n '\b(head|tail|init|last|read|fromJust|fromRight|fromLeft|maximum|minimum)\b|!!|\berror\b|undefined|TODO' --glob '*.{hs,lhs}'
rg -n 'Non-exhaustive|incomplete-(patterns|uni-patterns)|-Wno-incomplete' . --glob '*.{hs,lhs,cabal,project}'

# Deriving, classes, orphans, coercion, and roles
rg -n 'deriving (stock|newtype|anyclass|via)|DeriveAnyClass|GeneralizedNewtypeDeriving|StandaloneDeriving' --glob '*.{hs,lhs}'
rg -n '^instance |OVERLAPP|INCOHERENT|UndecidableInstances|type role|\bcoerce\b|unsafeCoerce' --glob '*.{hs,lhs}'

# Extension policy and documentation evidence
rg -n 'LANGUAGE|default-extensions:|other-extensions:|StrictData|TemplateHaskell|-fplugin' --glob '*.{hs,lhs,cabal}'
rg -n '^-- \||^-- \^|^-- \$|^class ' --glob '*.{hs,lhs}'
cabal haddock all --haddock-all
```

Grep hits are leads, not findings. Determine whether a module is public, whether
constructors intentionally expose representation, and whether an instance or
extension is required by an established design. Judge types by the invalid
states they prevent, the contracts they communicate, and the migration burden
they impose, not by type-level sophistication.
