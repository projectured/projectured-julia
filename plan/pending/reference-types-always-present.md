# Reference types always present (strict DSL enforcement)

Make the reference-path type-checkpoint an **always-populated** invariant, so
every path in the tree carries its types at every node. `@reference` requires
`::T` after every navigation step; there is no plain skeleton form. Types are
load-bearing — a stored path validates by asserting each recorded type against
the node it stands on.

## Problem

Reference paths currently exist in two forms:

- **Plain skeleton** — `@reference` at macro-time can't know the types, so
  every navigation step's `type` field starts `nothing`.
- **Annotated (canonical)** — `set_selection!` walks the document and fills
  each step's `type` in.

Two forms means five conversion / comparison functions on the public API
(`is_reference_equal_ignoring_types`, `is_prefix_of_ignoring_types`,
`strip_reference_types`, `annotate_reference_types`, `fold_reference_types`),
and ~10 defensive `strip_reference_types(x)` calls across kernel/base/visual —
each a "I don't know which form this is" bandage.

## Design decision

**Strict DSL enforcement (Q1-A):** every navigation step in `@reference` is
followed by `::T`. A step without a type annotation is a parse error, not a
skeleton — the plain form never exists.

Rationale:

- **Reader value.** The types spelled at every step make the shape of the
  reference explicit at the call site. A reader sees the intended trajectory
  through the document schema without opening the domain code.
- **Load-bearing validation.** Every recorded type is asserted at runtime by
  `get_valid_reference_prefix` / `evaluate_reference`. A stored path that has
  survived a structural change is caught at exactly the step where its
  assumption broke.
- **Precedent.** The Lisp implementation of ProjecturEd required types at
  every step for the same reasons.

### DSL grammar

- **Navigation step + type:** `entries::T`, `[i]::T`, `.field::T`, `{k}::T`.
- **Leading `::T`.** Optional — records the type of the starting node. Elided
  = polymorphic root (starting node type unknown until application). Most
  domain call sites carry it; generic combinator sites in base often elide.
- **Splices `^(expr)`:** the spliced path carries its own types (runtime
  guarantee, verified by construction at all producer sites). The chain
  *after* the splice must still be typed at every step; the splice itself is
  opaque and its terminal type contributes to whatever comes next.
- **Trailing type in a whole-element path.** `@reference` (empty) → an
  `EmptyReferencePath` with an optional leading `::T` recording the terminal
  node's type. Also elided when polymorphic.

The current DSL already parses `.field::T` and `::T.rest` as folded
`TypeReference` steps — enforcement is at the parse stage: every navigation
step must be followed by a `::T` (folded onto the tail node's type field).

## Rollout

Each step is a real commit, tree stays green throughout.

1. **This plan document.** Filed alongside the migration.
2. **Add strict-parse mode** to `ReferenceBuilder.jl`, off by default (an
   opt-in `strict = true` on the internal parse entry point). No user-visible
   behaviour change yet — migration below flips call sites to be *ready* for
   strict, but strict isn't the default.
3. **Migrate `@reference` call sites, package by package.** Each package is
   one (or a small handful of) commits:
   - kernel: ~34 sites
   - base: ~5 sites
   - odbc: ~13 sites
   - sdl: ~6 sites
   - visual: ~76 sites
   - domain: ~315 sites (by domain slice: json / xml / yaml / sql / graph /
     workbench / …)

   For each site, add `::T` after every navigation step. Types come from the
   domain's `@document` schema (grep `struct` / `@document` for the field
   types). Splices propagate their types by construction.
4. **`@reference_case` patterns** get the same treatment where they name
   step types — the pattern grammar already supports the same `::T` suffix.
5. **Flip the DSL to strict.** Parse error on any untyped navigation step
   in `@reference`. All migrated sites keep working; any survivors surface as
   compile-time failures.
6. **Retire `strip_reference_types` / `annotate_reference_types` /
   `fold_reference_types` from public exports.** They stay as internal
   machinery of `set_selection!` and the DSL builder; every previous external
   call becomes obsolete under the invariant (paths arriving at any consumer
   are always canonical) and gets deleted or, in a handful of kernel-internal
   places, becomes qualified inline access.
7. **Retire `is_reference_equal_ignoring_types` / `is_prefix_of_ignoring_types`**
   — done in an earlier commit; comparisons are strict throughout.
8. **AR-audit + seal `reference/ReferenceModule.jl`.** Everything the plan
   sets up as final is now in place.

## Consequences

- Every `@reference` call site in the tree is annotated. Grep for
  `@reference` yields self-documenting paths.
- The `strip_reference_types(x)` bandage disappears — 10-ish call sites in
  base/visual either delete the call (the source is already canonical) or
  become obsolete alongside the operations they normalized for.
- `annotate_reference_types` becomes purely internal — `set_selection!`
  still calls it while it canonicalizes, but no outside code sees it.
- `fold_reference_types` becomes DSL-internal — the parser calls it when
  building a path from the parsed AST; no outside code sees it.
- `is_reference_equal` becomes the one comparator, strict on the canonical
  form, working correctly because both sides always carry their types.

## Scope estimate

- Steps 1–2: small, this session.
- Steps 3.kernel + 3.base + 3.odbc + 3.sdl: ~60 sites, this session.
- Step 3.visual: ~76 sites, likely this session (may spill).
- Step 3.domain: ~315 sites, multiple sessions.
- Steps 4–8: final coordinated session once step 3 is complete.

Multi-session, with each commit landing a green tree.
