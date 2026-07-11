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
  **synthetic value** — a `Coord(x, y)` for `PointReference`, a
  `(projection, output_path)` tuple for `ProjectionReference`, a substring
  for `TextRectangularReference` — anything evaluatable. The reference is
  never *dead-endable*.
- **D3-a — rewrite kernel builder tests** using placeholder types
  (`ToyType`, `Any` where the specific type is beside the point). Update
  expected `ConcreteReferencePath` / `EmptyReferencePath` constructions to
  include the type argument.
- **D4-a — strict patterns.** `@reference_case` patterns spell types the
  same way; the runtime match compares node types alongside navigation
  steps. Tolerant matching (currently used for `::T` in patterns) is retired.

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

1. **This plan document** with the locked decisions above.
2. **Strict-parse mode in the DSL builder** — a per-invocation opt-in
   `strict = true` on the internal parse entry point. Untyped nav steps
   error. Kept off-by-default so migration can proceed with the tree green.
3. **Update `evaluate_step` for terminal step types** — `PointReference`
   returns `(x, y)`, `ProjectionReference` returns
   `(projection, output_path)`, `TextRectangularReference` returns
   `(start, stop)`. `step_kind` for these becomes `:structural`. Update
   `evaluate_reference` / `get_valid_reference_prefix` / walkers to route
   through the seam uniformly. Includes updating documentation.
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
