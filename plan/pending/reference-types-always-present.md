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
3b. **DSL PARSER prerequisite — split `.field`/`[i]` after a mid-path
   `::Type` (BLOCKS the domain migration).** Discovered while migrating JSON:
   the chained typed form `entries::CellVector[i]::JsonObjectEntry.key::String{0}::Position`
   does not parse as intended. Julia binds `Type.field` (getfield on the type
   value) tighter than `::`, so `::JsonObjectEntry.key` parses as
   `::(getfield(JsonObjectEntry, :key))` — the `.key` is absorbed into the
   type instead of becoming a new field step. (`::Type[i]` and `::Type{k}`
   already work — `_build_type_suffix!` handles the curly/ref cases; only a
   `.field` after a mid-path `::Type` is broken.) The leading case
   `::JsonObject.entries` works because `_build_leading_type!` special-cases
   it (first symbol = type, rest = field steps).

   Fix: teach `_build_type_suffix!` (ReferenceBuilder) and `_pat_type_suffix!`
   (ReferenceCase) that when the type expression is a `.`-chain
   (`A.b.c`), the leftmost symbol is the `BSType`/`PSType` and the trailing
   parts are field steps — mirroring `_build_leading_type!`. Add a kernel
   builder/eval test constructing a multi-step typed path
   (`::T1.a::T2.b::T3`) and asserting the folded node types. Empirically
   verified: `dump(:(x::A.b::C))` shows left-associative `::` nesting with
   `A.b` as a getfield expr, so the flatten is well-defined.

   Sites that parse today (no `.field` after a mid `::Type`) can migrate
   before the fix; sites with it are blocked until 3b lands. Do 3b first.

4. **Migrate `@reference` / `@reference_case` call sites**, package by
   package. For each site:
   - Add `::T` after every navigation step (structural + splice + previous
     terminal). Types match `annotate_reference_types`' canonical output.
   - Add leading `::T` where the root type is known.
   - Cursor terminals record `::Position` (the value a `{k}` evaluates to).
   - Update `EmptyReferencePath()` no-arg call sites to spell the type.
   - Update `@reference_case` patterns to include types.

   **Note on `with_selection` sites:** `set_selection!` currently
   strips+re-annotates, so the DSL types on those sites are normalized to the
   runtime document's types (cosmetic until step 6 retires the strip). They
   must still parse and be readable/correct. Primitive value cursors
   (`value{k}` on a JsonNumber holding `nothing`) annotate to the runtime
   value's type (`Nothing`/`Int`/…), which the DSL literal should match.

   Order (small first):
   - kernel main: 2 sites — ✅ (identity maps typed via `reference_node_type`).
   - base: generic combinators — ✅ (Reversing/Filtering/Sorting rebuilt
     steps typed). Searching + Focusing deferred (strip-entangled).
   - kernel tests: ~30 sites (builder + eval tests rewritten).
   - odbc: ~12 sites.
   - sdl: ~6 sites.
   - visual: ~54 sites.
   - domain: ~298 sites, batched by domain slice — ✅. Migrated: json, xml,
     yaml, sql, formula, graph, book, markdown, insertion, workbench. Verified
     already-typed / no migration needed: filesystem, math, dbcatalog.
     Convention settled during migration (matches SQL): **construction-side
     `@reference` rebuilds carry a single leading `::T` (the mapper's output
     type forward / input type backward); intermediate index/field nodes and
     the splice-covered tail stay untyped until the step-5 strict flip.**
     `@reference_case` *patterns* are largely left untyped in step 4 (only
     type-bind/assert patterns that were naturally needed got types) — full
     strict patterns (D4-a) land with step 5. Terminal (splice-less) selection
     constructions get the leading `::T` only where the element type is
     heterogeneous and `CellVector`/`Document` are not imported in the slice's
     module (e.g. `WorkbenchToWidget`'s `@reference ::WorkbenchPage.elements[idx]`);
     step 5 adds the missing imports + full index/terminal types uniformly.
5. **Flip DSL to strict** — ✅ **DONE (2026-07-12).** `STRICT[]=:error` is the
   committed default; every 1-arg `@reference` requires a fully typed path or
   throws at construction. All four main suites pass under enforcement: kernel
   338, base 82, visual 51848, domain 132968 (0 fail/error). Every `@reference`
   construction site in kernel/base/visual/domain **main + tests** is fully typed
   (0 under-typed), plus domain/example, sdl/example, odbc (peripheral, typed
   best-effort — sdl/odbc unverifiable without SDL2/ODBC drivers). Key mechanisms
   that landed: doc-annotating `make_child_context` (typed ctx.reference through
   the print recursion); generic template + **default** projection mappers
   self-type their output against the iomap document (Option A — no boundary
   band-aids); raw builder/eval/rerooting/point-reference primitive tests wrapped
   in `STRICT=:off` (they test untyped-skeleton construction); `proj`-wrapped
   backward maps use the 2-arg `@reference(doc, proj…)` form (annotates without
   tripping the construction-time check); leaf char-ranges terminate in
   `::Position`. **D4-a (`@reference_case` pattern typing) — ✅ DONE
   (2026-07-12):** a leading `::T` on ~95 navigation patterns (domain 88, visual
   7, json, plus the pre-existing SQL step-4 ones), `T` = the type the matched
   reference is rooted at. A pattern `::T` is a **tolerant** assertion (never
   fails a match, by design for re-rooted selections) — documentary symmetry
   with construction, not enforcement; suites green. Genuinely-generic patterns
   left untyped: base higher-order combinators (`IoMap.input/output::Any`), the
   kernel default map (`∅`/`proj` only), and a few abstract-projection cases
   (MarkdownStyledInline, InsertionToSyntaxLeaf, SqlBooleanBinaryToSyntaxNode).
   **Below is the original plan for the record.**

   **Confirmed user decisions (2026-07-11):**
   - **Full per-node typing** — every navigation node carries `::T` matching
     `annotate_reference_types`' canonical output; "types always present. period."
   - **Spell `::CellVector` at every index explicitly** (no auto-supply in
     fold): a bare `xs[i]` becomes `xs::CellVector[i]`, matching the json slice.
     `CellVector` is imported into every slice that indexes a collection.

   Real scope (measured 2026-07-11): ~117 main `@reference` sites still carry a
   bare `[i]` (only 19 already json-style); ~68 test `@reference` (1-arg) sites
   need inline types or conversion to `@reference(doc, …)`; ~202 `@reference_case`
   patterns need typed patterns (D4-a); plus every `EmptyReferencePath()`
   fallback needs its type. Step 4's leading-`::T`-only convention was an
   intermediate — this step tightens every slice to full fidelity.

   Execution: build a transitional strict checker (`is_fully_typed` +
   `_strict_check` behind a `STRICT[] ∈ (:off,:warn,:error)` flag wired into
   `@reference`) as the per-file acceptance test — **done, committed**; convert
   package-by-package (kernel→base→visual→domain) in `:warn` mode, then flip
   `STRICT[]=:error` as the default once every suite is warn-free. Any missed
   untyped nav step then surfaces as a runtime failure at path construction.

   **Enumeration (2026-07-11, STRICT=:warn):** kernel main + base = 0 (already
   clean); kernel test = 27 raw builder/eval primitive sites (deliberately test
   skeletons → wrap in `STRICT=:off` at flip, not typed); visual main = 29,
   visual test = 13; domain main = 95 (SQL 46, workbench 11, math 7, graph 5,
   book 3, formula 3, insertion 2, …), domain test = 22. NOTE the checker only
   flags `@reference` sites, NOT raw `make_child_context(ctx, FieldReference…)`
   sites (ProjectionTemplate + some printers), which also build untyped
   `ctx.reference` and must be converted separately.

   **ctx.reference decision (user, 2026-07-11): type it fully.** Implemented the
   core: `make_child_context(ctx, current_doc::Document, steps...)` annotates the
   appended steps against the current document and concats onto the parent ref
   (PrinterContext.jl) — replaces the `@reference ^(ctx.reference).field` splice.
   Formula slice fully typed as the pilot (0 under-typed, green). **Committed.**

   **Open fork — child mapper output typing (blocks the domain grind):** a parent
   mapper splices `^(inner)` where `inner = map_reference_forward(child.projection,
   child, rest)`. Generic children — `ProjectionTemplate` atomic/opaque wiring and
   `ProjectionReference`-wrapped cursor paths — return structurally-correct but
   *untyped* sub-paths, so the spliced result is under-typed. Typing the atomic
   whole-node empties (`_atomic_forward/backward` opaque `∅ ⇒ _typed(w.outtype/intype)`)
   helped but left the ProjectionReference/cursor case (SQL: 46→24). Two ways:
   - **A (source typing, pure):** type `ProjectionReference.output_path` at
     construction + the atomic transparent/cursor paths, so children always emit
     typed sub-paths. No consumer changes; touches delicate generic core.
   - **B (boundary annotation, one helper):** a single `mapped_forward/backward`
     wrapper — `r === nothing ? nothing : (is_fully_typed(r) ? r :
     annotate_reference_types(child.output/input, r))` — that every mapper routes
     child recursion through. Localized, uniform, uses the in-hand child doc; a
     re-annotation pass (the rejected per-site band-aid, formalized into ONE
     helper). **Awaiting user decision.**
6. **Retire** `strip_reference_types`, `annotate_reference_types`,
   `fold_reference_types` **from exports.** **RECONSIDER (2026-07-12):** these
   turned out to be *load-bearing*, not transitional — `annotate_reference_types`
   powers the 2-arg `@reference(doc, …)` form and the generic/default mapper
   self-typing; `strip_reference_types` is used at boundaries (set_selection!,
   test navigation-shape comparisons); `fold_reference_types` backs the `::T`
   DSL. So they stay exported/public; step 6 is now just a tidy pass, not a
   removal. `is_fully_typed` was added and exported (used by ProjectionTemplate).
   **DONE (2026-07-12): removed the transitional `STRICT` `Ref` (`:off`/`:warn`/
   `:error`) and the `_UNDERTYPED` collector** — enforcement is now fixed and
   unconditional (`_strict_check` always throws on an under-typed `@reference`).
   The builder/eval/rerooting/point-reference tests that used the `:off` escape
   hatch were rewritten (D3-a) to build typed paths (compared via
   `strip_reference_types`, or built directly for the `.point` extension step,
   which has no inline `::T` form).
7. **AR-audit ReferenceModule.jl** and **stop for user review before
   sealing** (user has explicitly asked for a review checkpoint here). — the
   next action. D4-a (`@reference_case` pattern typing) is separable and can
   follow either before or after the seal, at the user's discretion.

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
