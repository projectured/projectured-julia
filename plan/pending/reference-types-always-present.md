# Reference types always present (no plain skeleton form)

Make the reference-path type-checkpoint an **always-present** invariant, so
the module's public API never needs to distinguish "plain" from "annotated"
paths. `@reference` stays document-less; every path it produces carries its
types from the start. Every path is validated when applied to a document.

## Problem

Reference paths currently exist in two forms:

- **Plain skeleton** — produced by `@reference` at macro-time, when no
  document is in hand. Every step's `type` field is `nothing`.
- **Annotated (canonical)** — produced by `set_selection!` via
  `annotate_reference_types(document, plain_path)`, which walks the document
  and fills each step's `type` with `typeof(node)`. This is what selections
  actually store.

Two forms means five public functions exist only to convert between them or
to compare them modulo type checkpoints:

- `is_reference_equal_ignoring_types` / `is_prefix_of_ignoring_types` —
  compare when one side is plain and the other is canonical.
- `strip_reference_types` — canonical → plain.
- `annotate_reference_types` — plain → canonical.
- `fold_reference_types` — a `TypeReference` step collapses into the
  following step's `type` field. Only the `@reference` DSL needs this (it
  emits both kinds of AST fragments), but it currently sits on the public
  API surface too.

Consumers all over the tree call `strip_reference_types` defensively to
normalize before comparison or iteration
(`base/document/Primitive.jl:135,154`, `base/projection/Searching.jl:145`,
`base/projection/generic/Focusing.jl:60`,
`visual/clipboard/ClipboardToAny.jl:484`,
`visual/text/SelectionInverting.jl:289,310`, plus test sites and internal
`kernel/operation/Operations.jl` machinery). Each of those calls is
essentially "I don't know whether this path is annotated or not, strip to
be safe" — the smell the invariant is meant to remove.

## Goal

References always carry their types. Every path is either:

- an `EmptyReferencePath`, or
- a `ConcreteReferencePath` whose every step has a fully-populated `type`
  field.

Consequences:

- The five functions above stop being part of the module's exported surface.
  They may still exist as internal helpers for the DSL fragment and for
  `set_selection!`'s validation walk, but nobody outside the module needs
  them.
- Path equality is just `is_reference_equal`; prefix check is
  `is_prefix_of`. The `_ignoring_types` variants disappear.
- Comparison-normalization at consumer sites (the ~10 `strip_reference_types`
  calls listed above) go away.

## Design questions

### Q1 — Where do the types come from?

`@reference` runs at macro-expansion time and doesn't have a document in
hand. Two options:

- **Q1-A: Explicit per-step types in the DSL.** `@reference [1]::T.field::U`
  — the user names the type at each step. Concrete and immediate but noisy
  for common cases; how to elide `T` when it's obvious to the reader may
  need thought.
- **Q1-B: Deferred fill at first application.** `@reference` produces steps
  with `type` cells that are `nothing`; the first application to a document
  (via `evaluate_reference` / `set_selection!`) fills them in and *keeps*
  them, so subsequent operations see canonical paths. This preserves DSL
  ergonomics but keeps a "not-yet-filled" transient state.
- **Q1-C: Reject `@reference` skeletons entirely; require the programmatic
  builder** (`@step` / manual `ConcreteReferencePath` construction) for
  cases that need explicit types, and let the DSL only produce paths that
  can be inferred (e.g. field references where the enclosing struct
  determines the type).

Q1-B keeps existing call-site ergonomics best but the "first application
mutates the path" is subtle; Q1-A is honest but noisy.

### Q2 — When does validation happen?

Even under Q1-B, the type field is filled from the *current* document at
first application. If the document later mutates (a shape change), the
stored type is now wrong. Validation must run at every subsequent use to
catch the mismatch, and the invariant becomes "types are present AND
current at time of use", enforced by validation, not just by construction.

`get_valid_reference_prefix` already exists as the truncation-on-mismatch
walk. Under the new invariant, its role expands: every use of a reference
routes through it (or its return value is guaranteed correct because the
last write walked the same path).

### Q3 — What replaces the ~10 `strip_reference_types` call sites?

Each site has to be classified:

- Some are asking "match against a plain user-built path" — those go away
  once user paths are also canonical.
- Some are iterating steps and expecting no free-standing `TypeReference`
  steps — those go away because the invariant means folded checkpoints are
  the only form (a bare `TypeReference` step is only a build-time DSL
  artifact `fold_reference_types` already resolves).
- Some are semantic — they want to compare "does path A navigate to the
  same *shape* as path B, regardless of which node types happen to sit on
  it right now" — those keep needing a shape-only comparator, but under a
  new name that's honest about what it does (e.g. `same_navigation` or
  similar), not "ignoring types".

Each existing call site should get audited during migration to decide which
bucket it falls in.

## Rollout

1. **Design decisions.** Pick Q1-A vs Q1-B vs Q1-C. Decide the migration
   shape for the `_ignoring_types` semantic-comparison use case (Q3).
2. **`Reference.jl`.** Enforce the invariant at the type / constructor
   level (types-present ConcreteReferencePath constructors); mark the
   internal-only helpers `_`-prefixed so they clearly aren't public.
3. **Move `annotate_reference_types` into `set_selection!`'s implementation
   as an internal step,** dropping the export.
4. **`ReferenceCase.jl`.** The DSL emits `is_reference_equal` /
   `is_prefix_of` directly instead of `_ignoring_types` variants.
5. **`ReferenceBuilder.jl`.** Whichever of Q1-A/B/C is chosen, the DSL
   producer changes accordingly; `fold_reference_types` becomes an internal
   helper `_fold_types` (or is inlined).
6. **Consumer migration.** For each `strip_reference_types` /
   `annotate_reference_types` / `_ignoring_types` call site outside the
   module, apply the Q3 classification and either delete the call, replace
   with the plain equality, or wire through the new shape-only comparator.
7. **Un-export the five functions** from `ReferenceModule.jl` and drop them
   from `import ..ReferenceModule: …` sites.
8. **Guards + tests.** `test_kernel_layering()`, `test_kernel()`,
   `test_base()`, `test_visual()`, `test_domain()`. The kernel guard's
   `check_private_imports` proves the un-export took (any surviving import
   of the five names becomes a guard failure).

## Blast radius

- ~15 `strip_reference_types` / `annotate_reference_types` /
  `_ignoring_types` call sites across kernel/base/visual/domain to audit
  and rewrite.
- `@reference` DSL semantics change slightly depending on Q1.
- `set_selection!` internal shape changes (annotation moves inside).
- No user-facing API is added; several are removed. Callers who were doing
  the right thing (using `is_reference_equal`, iterating steps naïvely) are
  unaffected.

## Related

- Blocks the AR-audit / seal of `reference/ReferenceModule.jl` — the
  audit flagged the five exports as leftover machinery from a design
  choice the module is trying to move past.
- Later: consider whether the `TypeReference` step type is still needed as
  a public export at all, given that under the invariant it exists only as
  a build-time DSL artifact.
