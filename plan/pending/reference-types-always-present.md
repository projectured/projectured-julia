# Reference types always present (strict DSL enforcement)

Every reference path in the tree carries its types at every node. `@reference`
requires `::T` after every navigation step — including terminal-like step
types (`.proj`, `.point`, `.rect`). `EmptyReferencePath()` (no-arg) is gone;
an empty path is a *type reference* to an object of a specific type. Types
are load-bearing (validated at runtime) and reader-serving (the schema
trajectory is explicit at every call site).

## Locked design decisions

- **D1-b — no `nothing` types.** `EmptyReferencePath` requires a type. A path
  referring to an object without further navigation is a **type reference**
  spelled `::T` (an empty path whose terminal type is `T`).
- **D2-b — every step is descending and every step is typed.** Structural,
  splice, and previously-terminal steps all descend to a value on evaluation
  and all carry a `::T` after them naming the resulting node's type. For step
  types that don't correspond to a document field, the descent returns a
  **synthetic value** — a coordinate pair for `PointReference`, the output
  path for `ProjectionReference`, a range for `TextRectangularReference` —
  anything evaluatable. The reference is never *dead-endable*.
- **D3-a — rewrite kernel builder tests** using placeholder types
  (`ToyType`, `Any` where the specific type is beside the point). Update
  expected `ConcreteReferencePath` / `EmptyReferencePath` constructions to
  include the type argument.
- **D4-a — strict patterns.** `@reference_case` patterns spell types the
  same way; the runtime match compares node types alongside navigation
  steps. Tolerant matching (currently used for `::T` in patterns) is retired.

### Surface syntax (confirmed)

Leading type on every node **plus** the trailing terminal type — the
`::T1.f::T2` form. For a JSON path into `JsonObject → entries[i] → value`:

```julia
@reference ::JsonObject.entries::CellVector[i]::JsonObjectEntry.value::JsonString
```

The existing fold machinery (`fold_reference_types`) already turns this into
the folded form (each node carries the type of the node its step descends
from; the terminal carries the landed type) — `n` navigation steps yield
`n+1` typed nodes. A whole-element / type reference with no navigation is
`@reference ::T`; the no-arg `@reference()` is **removed**.

### Generic / polymorphic code — type-binding DSL feature

Generic reference-transforming code (the `map_reference_forward`/`backward`
defaults, the base combinators — Chaining, Sorting, Focusing, …) runs for
every domain and cannot name a concrete type. It satisfies the invariant by
**binding** the type in the pattern and **splicing** it back in construction:

```julia
function map_reference_forward(p, iomap, reference)
    @reference_case reference begin
        (∅::t)            => @reference ::^(t)   # identity, type preserved
        proj(^(p), inner) => inner
    end
end
```

New DSL machinery this requires:

- **`@reference_case`: type-binding patterns.** `::t` where `t` is a
  lowercase identifier binds the matched node/terminal type to `t` (like a
  value pattern variable, but for the folded `type` field). A `::T` where `T`
  resolves to a type value stays an assertion.
- **`@reference`: type-variable splicing.** `::^(expr)` (or `::$(expr)`)
  uses the runtime *type value* `expr` as the node/terminal type, rather than
  a literal type name. Lets generic code reconstruct a path carrying a type
  it bound rather than one it named.

The ~40 generic kernel/base sites migrate using these; the ~450 concrete
domain/visual sites use literal `::T` names.

## Consequences

- `strip_reference_types`, `annotate_reference_types`, `fold_reference_types`
  become internal to `ReferenceBuilder.jl` and `set_selection!` — under
  strict, every path arriving at any consumer is fully typed, so the
  compare-modulo-types machinery has no external use.
- `EmptyReferencePath()` (no-arg) is removed; every construction spells a
  type.
- Every terminal step type — `ProjectionReference`, `PointReference`,
  `TextRectangularReference` — gains an `evaluate_step` method (per its
  home package). They stop being `:terminal` in `step_kind`; the
  classification collapses to `:structural` (descends) vs `:checkpoint`
  (asserts on the current node, `TypeReference`).
- The DSL's `.point`/`.proj` DSL entries require `::T` after them; the T
  is the type of the synthetic value they descend to.
- Every `@reference` and `@reference_case` in the tree is annotated —
  ~500+ call sites across 6 packages, migrated package by package.

## Rollout

Each numbered step is at least one commit; the tree stays green throughout.
The last step is a review checkpoint (user approves before I mark sealed).

1. **This plan document** with the locked decisions above. ✅
2. **DSL feature: type-binding + type-splicing.** `@reference_case` binds a
   node/terminal type with `::t` (lowercase → variable); `@reference`
   splices a runtime type value with `::^(expr)`. Enables the generic-code
   migration without a concrete type. Add tests for both.
3. **Update `evaluate_step` for terminal step types** — `PointReference`
   returns `(x, y)`, `ProjectionReference` returns its output path,
   `TextRectangularReference` returns `(start, stop)`. `step_kind` for these
   becomes `:structural`. Walkers route through the seam uniformly. ✅
4. **Migrate `@reference` / `@reference_case` call sites**, package by
   package. For each site:
   - Add `::T` after every navigation step (structural + splice + previous
     terminal).
   - Add leading `::T` where the root type is known.
   - Update `EmptyReferencePath()` no-arg call sites to spell the type.
   - Update `@reference_case` patterns to include types.

   Order (small first):
   - kernel main: 2 sites (both need updating for D2-b).
   - kernel tests: ~30 sites (builder + eval tests rewritten).
   - base: ~4 sites.
   - odbc: ~12 sites.
   - sdl: ~6 sites.
   - visual: ~54 sites.
   - domain: ~298 sites, batched by domain slice.
5. **Flip DSL to strict** — one commit. `strict = true` becomes the default;
   any missed untyped nav step surfaces as a compile-time failure.
6. **Retire** `strip_reference_types`, `annotate_reference_types`,
   `fold_reference_types` **from exports.** Update kernel-internal callers
   (in `Operations.jl`, `ProjectionTemplate.jl`) to use qualified inline
   access.
7. **AR-audit ReferenceModule.jl** and **stop for user review before
   sealing** (user has explicitly asked for a review checkpoint here).

## Scope estimate (multi-session)

- Step 1: this session. Small.
- Step 2: this session. Small parser change plus tests.
- Step 3: 1–2 sessions. Redefining `evaluate_step` for three types plus
  audit of every walker + call chain.
- Step 4: several sessions. ~500 sites, domain schema knowledge per batch.
- Steps 5, 6, 7: one coordinated session at the end.

## Related

- Pairs with `plan/done/reference-step-cleanup.md`. That plan restructured
  the *type registry* (step types moved out of the kernel reference layer).
  This plan tightens the *type invariant* on the paths those types describe.
