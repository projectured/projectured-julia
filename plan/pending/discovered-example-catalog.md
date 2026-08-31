# Discovered example catalog: document/projection pairs as data, not fragments

> **Status (2026-08-12): SUPERSEDED.** Phase 0 (the projection graph +
> `Example.terminal`) landed and is the foundation; its symbols
> (`catalog_domain`, `BRIDGES`, `paths`, …) live in
> `package/projectured/example/Catalog.jl` and
> `package/projectured/example/ProjecturedExample.jl` today. Phases 1 to 3 —
> document *generation* via `minimal()` and the `@document` / `CellVector{T}`
> reflection track — are **superseded** by
> [`plan/done/atomic-example-catalog.md`](../done/atomic-example-catalog.md),
> which instead **hand-authors** the atomic documents (meaningful content, no
> `minimal()`) and keeps only the *projection* discovery automated. That plan is
> itself fully done and moved to `plan/done/`. Read it for the current approach;
> this file is kept for the Phase 0 record and the projection-graph design notes.

## The idea (one paragraph)

Build a **generated catalog of `(document, projection)` pairs** that serves double
duty as *test fixtures* and *runnable examples*. The pairs are **discovered**, not
hand-enumerated: every projection stage already declares the document type it
consumes (`@projection_template JsonNullToSyntaxLeaf JsonNull …` expands to
`print_document(p::JsonNullToSyntaxLeaf, recursion, doc::JsonNull, ctx)`), so the
document↔projection edges live in the method table of `print_document`. Document
instances are produced by a generic **minimal instantiator** driven by the declared
field types the `@document` macro already captures. To reach a target domain a test or
live example needs (`Text`, `Graphics`), we **search a projection graph** for the minimal
chains `X → … → Y` — because a projection's *output* type is not static, edges resolve by
run-and-inspect on minimal documents, over a small runnable **bridge** edge set. The whole
thing collapses to writing **O(N) building blocks** (one base-case per primitive, ~O(domains)
bridge edges) instead of **O(N×M) fixture fragments**, and both *which tests apply* and
*whether a pair is runnable on screen* are pure functions of a single derived field — the
projection's **terminal domain**.

This is a **narrower, additive** revival of the abandoned
[`plan/obsolete/test-suite-atomization.md`](../obsolete/test-suite-atomization.md).
It deliberately does **not** replace the ~88-example registry, does **not** delete
the per-stage `test_<proj>()` functions, and does **not** retier the dev loop. It
adds a new, generated catalog alongside what exists. It may or may not subsume the
old fixtures later; that is out of scope here.

## Prior art in the tree

- `AtomicFixtureTest.jl` — the POC `AtomicFixture` with `make_document`/`make_projection`
  thunks + oracle fields this section describes no longer exists in the tree; its
  thunk-for-freshness shape and its oracle fields were carried into
  [`plan/done/atomic-example-catalog.md`](../done/atomic-example-catalog.md) instead.
- `Example` (`struct Example` in
  [`Harness.jl`](../../example/kernel/Harness.jl)) — the existing
  registry the testers already consume. Catalog entries **are** `Example`s (see "Data
  structure"), so `test_printer`/`test_reader`/`run_example` take them unchanged.
- The chain shape already exists in the wild (a hand-wired path the graph would synthesize):
  [`WorkbenchAssistant.jl:199`](../../package/workbench/main/WorkbenchAssistant.jl#L199)
  `ChainingProjection(RecursiveProjection(JsonToSyntax()), SyntaxToText(), …)`.

## The one pivot: `terminal domain`

Both applicability and runnability are functions of the projection's terminal domain:

| terminal | tests that apply | runnable as example? |
|---|---|---|
| `:syntax` (or `:abstract`) | printer, reader, repl | no (can't be shown) |
| `:text` | + text_navigation, typein | yes → console |
| `:graphics` | + (later: click, render) | yes → screen / web |

So we store the pivot per case and *derive* the rest — no O(tests×cases) flag matrix:

```julia
requires(::typeof(test_printer))         = nothing   # abstract output; any terminal
requires(::typeof(test_reader))          = nothing
requires(::typeof(test_repl))            = nothing
requires(::typeof(test_text_navigation)) = :text
requires(::typeof(test_typein))          = :text

applies(test, ex) = (r = requires(test); r === nothing || r == ex.terminal)
runnable(ex)      = ex.terminal in (:text, :graphics)    # graphics→screen/web, text→console
```

(Open question: confirm `test_repl` truly needs no `:text` terminal — verify in Phase 2.)

## Data structure: extend `Example`, don't add a parallel `Case`

An earlier draft proposed a separate `Case` struct. Don't — it is just `Example`
minus one field. `Example`
(`struct Example` in [`Harness.jl`](../../example/kernel/Harness.jl))
already is
`name + make_document + make_projection` (plus cached instances and optional
`render_width`/`render_height`). The *only* thing a catalog entry needs beyond that is
the **`terminal`** pivot. So **merge**: add one optional field to `Example`.

```julia
struct Example
    name; make_document; make_projection
    document; projection                 # cached instances (existing)
    render_width; render_height          # presentation hints (existing)
    terminal::Symbol                     # NEW: :abstract | :syntax | :text | :graphics
end
Example(name, mk_doc, mk_proj; render_width=nothing, render_height=nothing,
        terminal=:abstract) = ...        # existing call sites unaffected (new kw defaults)
```

Payoff: a generated entry **is** an `Example`, so it plugs straight into
`test_printer(example)` / `run_example(example)` / the screenshot gallery with **no
adapter** — exactly the "project down to `Example`" step a separate `Case` would have
forced. `domain` is derived from the document type's module; authored examples keep
`terminal=:abstract` (or a `terminal(example)` helper can classify on demand). `name`
is computed for generated entries — e.g. `"json_array→text"` (ladder),
`"json_null · json_null_to_syntax_leaf"` (discovered stage).

Eager instantiation is **not** a concern: minimal documents are tiny and building a
projection object is cheap — the expensive part is *running* the pipeline, which
filtering avoids (you only run the surviving subset).

**Not merged in:** `AtomicFixture`'s oracle fields (`render`/`mutate`/`render_after`)
are a test-only enrichment — keep them out of `Example`; revisit as a Phase 3
test-side field.

Filtering is just `filter` over `Vector{Example}`; every axis is a predicate on cheap,
already-present data:

```julia
filter(ex -> domain(ex) == :json,          catalog())   # by document domain (type's module)
filter(ex -> ex.terminal == :text,         catalog())   # by terminal (≈ by cost)
filter(runnable,                           catalog())   # the runnable gallery
filter(ex -> applies(test_text_navigation, ex), catalog())  # what a given test can run on
```

## How the two generators feed one vector

**A. Discovered atomic stage pairs** (fast; for printer/reader/repl):

```julia
function discover_atomic_pairs()
    examples = Example[]
    for m in methods(print_document)
        _, projT, _, docT, _ = m.sig.parameters        # (fn, p::ProjT, recursion, doc::DocT, ctx)
        docT isa DataType && docT <: Document || continue   # concrete doc ⇒ atomic stage
        hasmethod(minimal, Tuple{Type{docT}})   || continue
        is_leaf_document(docT)                  || continue  # node stage needs a `recursion`
                                                             # arg → left to reachability + AtomicFixture
        push!(examples, Example("$(snake(docT)) · $(snake(projT))",
                                () -> minimal(docT), () -> projT();
                                terminal = stage_terminal(projT)))  # run-and-inspect output, else :abstract
    end
    examples
end
```

Combinators (`RecursiveProjection`, `ChainingProjection`, `TypeDispatchingProjection`,
…) have a *generic* `doc` arg, so `docT <: Document` fails and they fall out of
discovery automatically — they are the hand-woven residue, deferred to Phase 3.

**B. Reachability cases** (to reach `:text`/`:graphics` for text-nav/typein and for
running): built by **pathfinding over a projection graph** — for each minimal document
(type `X`) and each target document type `Y ∈ {Text root, GraphicsDocument}`, find the
minimal chains `X → … → Y`, compile each to a `ChainingProjection`, and emit one
`Example` per path with `terminal = domain(Y)`. See "Projection graph & pathfinding".

`catalog()::Vector{Example} = [discover_atomic_pairs(); reachability_examples()]`.
`test_catalog(; filter=identity)` loops the existing testers over `filter(catalog())`
guarded by `applies`; runnable entries open directly via the existing
`run_example(example)` machinery (no adapter — they are `Example`s).

## Projection graph & pathfinding (generalizes the ladder)

Rather than a hand-written per-domain ladder, model projections as a **directed graph**
and *search* it: given the minimal input document (type `X`) and a target document type
`Y` a test expects (a Text-domain root for text-navigation, `GraphicsDocument` for
rendering), find **all minimal-length chains** `X → … → Y` and compile each to a
`ChainingProjection`. This is the literal "reach `Y` from the generated input" a test
needs, and it subsumes the ladder — the shared `Syntax→Text→Graphics` tail is expressed
**once** as edges and reused by every domain's path via BFS, not repeated per domain.

**The one hard constraint: a projection's *output* type is not recoverable statically.**
Confirmed both ways — the printer types only its input
([`SyntaxToText.jl:146`](../../source/syntax/SyntaxToText.jl#L146)
`print_document(p::SyntaxLeafToText, recursion, leaf::SyntaxLeaf, ctx)`), and the reader
dispatches on the *iomap*/operation, not the output document
([`SyntaxToText.jl:158`](../../source/syntax/SyntaxToText.jl#L158)
`read_intent(p::SyntaxLeafToText, iomap::SimpleIoMap, op)`). Type inference won't help
either — the reactive layer erases field types to `Cell`/`Any` (the same erasure the
`CellVector{T}` metadata relies on). So graph **edges cannot be built from the method
table alone**; the output type must come from one of:

1. **Run-and-inspect (zero fragments).** During the search, apply a candidate projection
   to the current minimal document and read `typeof(out)`. Documents are minimal so this
   is cheap, it needs *no declared output types*, and it validates each edge as it is
   taken (no dead-end type mismatches). Clean for whole-tree bridge projections; a bare
   *node* stage still needs its `recursion` wired (the node caveat again).
2. **A tiny bridge registry (~O(domains)).** Declare the whole-tree domain transforms —
   `RecursiveProjection(JsonToSyntax())`, `SyntaxToText()`, `TextToGraphics()`, … — once
   as runnable edges (a dozen or so, not per-pair fragments). Their *target* domain can
   still be found by run-and-inspect, so you declare only the edge's projection.

Recommended: a small edge set of runnable bridges (so running is clean) + `paths(X, Y)` =
BFS returning **all shortest paths**; `projection_to(X, Y)` picks one (shortest /
preferred edge) for a canonical example, while a test may run *all* minimal paths for
coverage — the literal reading of "all minimal combinations". Where more than one minimal
path exists (e.g. a direct `Json→Widget` alongside `Json→Syntax→Widget`), that ambiguity
is a feature for testing (run both) and a choice for a single example (pick one).

```julia
# ── Edges: a small set of runnable whole-tree bridge projections (thunks for freshness).
#    The only declared graph metadata — ~O(domains), not per-pair fragments.
const BRIDGES = Function[
    () -> RecursiveProjection(JsonToSyntax()),
    () -> RecursiveProjection(XmlToSyntax()),
    () -> SyntaxToText(),
    () -> TextToGraphics(),
    # …one thunk per whole-tree domain transform
]

# Run-and-inspect one edge: apply a bridge to `doc`, return the projected output — or
# `nothing` if it doesn't apply. No static domain table needed: a non-matching bridge
# either throws (caught) or returns the same type (a no-op, skipped). Cheap: `doc` is
# minimal. `print_document(proj, input).output` is the 2-arg driver (wires recursion+ctx),
# exactly as AtomicFixtureTest uses it.
function _step(mk, doc)
    out = try
        print_document(mk(), doc).output
    catch e
        e isa MethodError ? (return nothing) : rethrow()
    end
    typeof(out) === typeof(doc) ? nothing : out        # identity bridge ⇒ not an edge
end

# ── All shortest projection chains from a minimal `start` to the first frontier where
#    `reached(T)` holds. One ChainingProjection per distinct minimal path.
function paths(start, reached)
    T0 = typeof(start)
    reached(T0) && return Projection[IdentityProjection()]      # already in the target domain
    inst  = Dict{DataType,Any}(T0 => start)                     # a representative instance / type
    dist  = Dict{DataType,Int}(T0 => 0)
    preds = Dict{DataType,Vector{Tuple{DataType,Function}}}()   # T′ → [(pred T, bridge thunk)]
    queue = DataType[T0]; goal = nothing

    while !isempty(queue)
        T = popfirst!(queue)
        goal !== nothing && dist[T] ≥ goal && continue          # never expand past minimal depth
        for mk in BRIDGES
            out = _step(mk, inst[T]); out === nothing && continue
            T′ = typeof(out); d = dist[T] + 1
            if !haskey(dist, T′)                                # first discovery of T′
                dist[T′] = d; inst[T′] = out; preds[T′] = [(T, mk)]
                reached(T′) ? (goal = d) : push!(queue, T′)
            elseif dist[T′] == d                                # another equally-short path
                push!(preds[T′], (T, mk))
            end
        end
    end
    goal === nothing && return Projection[]                     # Y unreachable from X

    [ _compile(seq) for T′ in keys(dist) if dist[T′] == goal && reached(T′)
                    for seq in _chains_to(T′, T0, preds) ]
end

_compile(seq) = length(seq) == 1 ? seq[1]() : ChainingProjection((mk() for mk in seq)...)

# Every predecessor chain T ⇐ … ⇐ T0, returned start→…→T as ordered bridge thunks.
_chains_to(T, T0, preds) = T === T0 ? [Function[]] :
    [ [pre; mk] for (P, mk) in preds[T] for pre in _chains_to(P, T0, preds) ]
```

Usage — and the shape that feeds a reachability `Example`:

```julia
paths(minimal(JsonNull), T -> T <: TextDocument)      # ⇒ [Json→Syntax→Text]
paths(minimal(JsonNull), T -> T <: GraphicsDocument)  # ⇒ [Json→Syntax→Text→Graphics]
```

Notes: it's a standard **all-shortest-paths BFS** (level-synchronous via `dist`; `preds`
records *every* edge reaching a type at its minimal depth; `goal` caps expansion at the
first goal level). The only non-textbook part is that edges are discovered by *executing*
a bridge (`_step`) rather than read from a table — the answer to "output type isn't
static". **Memoize** `_step` on `(T, bridge-index)` so each bridge runs at most once per
type — important because the `TextToGraphics` bridge triggers the slow TrueType layout;
after the first search the graph is pure and reusable.

**Dedup bonus:** the hand-wired `_JSON_TO_TEXT` / `_XML_TO_TEXT` / … consts in
[`WorkbenchAssistant.jl:199`](../../package/workbench/main/WorkbenchAssistant.jl#L199)
are exactly what `projection_to(domain, TextDocument)` would synthesize — a real consumer
the graph could replace later.

## Minimal instantiation

`minimal(::Type{T})` builds the smallest valid instance by reading declared field
types (which the `@document` macro already captures — today as `field_names` /
`field_types` on the `CellStructPlan` built while the macro expands, in
[`CellStructPlan.jl`](../../source/kernel/cell/CellStructPlan.jl); the old
`original_fields`/`IFoo`-companion route this paragraph names no longer exists
under those names):

- **primitive field** (`value::Bool`, `Union{Real,Nothing}`, `String`) → base-case
  table: `Bool→false`, `Real→0`, `String→""`. ~3 lines, shared across all domains.
- **defaulted field** (`selection::Reference = nothing`, `collapsed::Bool = false`) →
  take the default; most container structs then instantiate *empty* with zero args.
- **abstract-typed field** (`JsonObjectEntry.value::Document`) → pick the minimal
  concrete subtype (`minimal_concrete(Document) = JsonNull`).
- **untyped container field** (`JsonArray.elements::CellVector`) → *empty* in Phase 0;
  *one minimal child of the declared element domain* once Phase 1 lands.

So `minimal(JsonArray)` is a legal empty array from day one; a one-element array needs
the element-domain annotation from Phase 1.

## Reconciling `AtomicFixture`

This section is superseded in fact, not only by name: `AtomicFixtureTest.jl` no
longer exists in the tree, and [`plan/done/atomic-example-catalog.md`](../done/atomic-example-catalog.md)
did the reconciliation this section proposes. Kept for the record of the reasoning.

`AtomicFixtureTest.jl` was
`Example`-core (`name` + `make_document` + `make_projection`) plus three **oracle**
fields (`render`/`mutate`/`render_after`) and a generic asserter `test_atomic_render`.
Its three core fields duplicate `Example`; its other two capabilities are **not**
subsumed by the catalog, so it stays — deduplicated, as the *golden + isolation* tier:

1. **Golden assertions.** `test_catalog`'s generic testers do no-throw/structural
   checks; they never assert `render(out) == "null"`. AtomicFixture's oracle is where
   the exact-render and reactivity goldens live.
2. **Node-stage isolation.** A *leaf* stage runs bare (`JsonNullToSyntaxLeaf` needs no
   `recursion`), so `discover_atomic_pairs` yields it directly. A *node* stage
   (`JsonArrayToSyntaxNode`) needs a `recursion` arg for its children — the catalog
   covers it only *in composition* (ladder, real children). Testing the node assembly
   *in isolation* means mocking children as already-projected values behind
   `Preserving` — AtomicFixture's `_json_array_node_projection` technique.

**Dedup:** rework `AtomicFixture` to *compose* an `Example` instead of re-declaring the
three core fields:

```julia
struct AtomicFixture
    example::Example                        # name + make_document + make_projection (+ terminal)
    render; mutate; render_after            # the golden-oracle delta
end
AtomicFixture(ex::Example; render=nothing, mutate=nothing, render_after=nothing) = …
```

So a fixture is built straight from a catalog `Example`
(`AtomicFixture(json_null_leaf; render="null")`) or hand-built for the mock-child
isolation cases; `test_atomic_render` reads `fx.example.make_document/make_projection`.

**Division of labor** (no overlap):

| tier | what | fidelity |
|---|---|---|
| `discover_atomic_pairs` | leaf stage, bare | stage in isolation, no children |
| ladder cases | domain → syntax/text/graphics | full real composition |
| `AtomicFixture` | node stage w/ mock children + goldens | assembly in isolation + exact oracle |

Consequence, already reflected in `discover_atomic_pairs` above: bare-stage cases are
emitted **only for leaf documents** (`is_leaf_document` — no child/container fields,
reflectable from `document_field_types`); node documents are left to the ladder
(composition) and `AtomicFixture` (isolation). Migration of the 7 existing json fixtures
(leaf goldens from catalog `Example`s; `json_array_node` kept as a hand-built mock-child
`AtomicFixture`) is Phase 3.

## Phase 1 detail: element-domain annotation on container fields

Goal: let `minimal` fill a container with one child of the right domain, driven by a
**declared annotation**, not a per-type override. Realize your "type parameter to
`CellVector`" idea as **metadata only** — which matches your own reasoning that
`@document` erases field types to `Cell`/`Any` at runtime, so `{T}` carries no runtime
weight. Concretely, we do **not** make `CellVector` a real parametric type (its storage
is already `elements::Vector{Cell}`, in [`Collection.jl`](../../source/collection/Collection.jl));
putting a concrete `CellVector{JsonDocument}` into the `IFoo` field would instead impose
a runtime invariant that every elements-vector actually *be* `CellVector{JsonDocument}`,
breaking snapshots). Instead:

- **Widen the macro's CellVector detection.** `@document` special-cases a
  collection field by a bare-symbol match on its declared type. Today this lives
  as `is_collection_field_type(::Val{name})`
  ([`DocumentMacro.jl:259`](../../source/kernel/document/DocumentMacro.jl#L259)),
  an opt-in trait rather than the plain `ftype === :CellVector` check this
  paragraph describes — re-check this note against the current mechanism before
  acting on it. Writing `CellVector{JsonDocument}` makes `ftype` an `Expr`, so any
  such check must match the *head* (`CellVector` with or without curly params) to
  preserve the existing Rule C/Y construction behavior.
- **Emit a queryable accessor.** Have `@document` generate
  `document_field_types(::Type{Foo}) = (…declared types incl. CellVector{JsonDocument}…)`
  from `original_fields`. This is one added method per struct — additive, and it gives
  `minimal`/discovery a clean handle for *all* fields (scalars and containers alike),
  without depending on the `IFoo` naming convention or imposing any runtime type.
- **Annotate container fields** (Json first): `JsonArray.elements::CellVector{JsonDocument}`,
  `JsonObject.entries::CellVector{JsonObjectEntry}`. Other domains follow incrementally.
- **Upgrade `minimal`** to read the element domain from `document_field_types` and fill
  the container with `[minimal(element_domain_type)]`.

⚠ `@document` is delicate — see the "Rule Y guard req≥1 → fatal precompile
method-overwrite" history. Keep this phase isolated and verify with `test_cell()` plus
the Json document/printer tests before moving on.

## Implementation notes (discovered during Phase 0)

The cell-kind refactor (see the "Cell-kinds review gate") changes the reflection surface
this plan assumed. Facts established by light-path probes against real types:

- **Document umbrella types are `UnionAll`s, not `DataType`s.** `JsonNull` is
  `JsonNull{K} where K` (kind `K`), `<: Document` but `!(JsonNull isa DataType)`; the
  concrete instance is `RJsonNull = JsonNull{Reactive}` and `IJsonNull = JsonNull{Immutable}`.
  `print_document` methods dispatch on the umbrella (`doc::JsonNull`). ⇒ discovery must
  filter on `isa Type`, **never** `isa DataType` (the latter silently drops every
  cell-kind document — 95 leaf stage pairs → 0). `nameof`/`parentmodule`/constructor
  (`JsonNull()`) all work on the umbrella; `RJsonNull()` (concrete) does **not**.
- **The `IFoo` companion's fields are `ImmutableCell{T}`, not `T`.** Unwrap the cell
  wrapper to recover the declared type the instantiator needs.
- **`CellVector` is already parametric on the cell kind** (`CellVector{K} where K`).
  So the Phase-1 idea "annotate `elements::CellVector{JsonDocument}`" collides with the
  existing kind parameter — the element domain would need a *second* parameter (or a
  separate `document_field_types` metadata accessor that does not touch the type). This
  materially raises Phase 1's cost/risk and interacts with the in-flight cell-kind work;
  **revisit Phase 1's mechanism before implementing.**

## Phases (each independently shippable; suite stays green)

- [x] **Phase 0 — catalog skeleton, no kernel change.** DONE (branch
  `discovered-example-catalog`). `Example.terminal`; `minimal` (containers empty); bridge
  edge set + run-and-inspect `path_sequences`/`paths`/`projection_to`; `discover_atomic_pairs`
  (leaf stages only) + `reachability_examples` (**`:text` and `:graphics`**);
  `runnable`/`catalog_domain`/`catalog(;…)`; `test_catalog` (`_required_terminal`/`_applies`
  in the test package). Core logic validated by light-path probe (minimal, is_leaf, 95
  discovered pairs, terminals, json/xml/array → text **and → graphics**).
  **Graphics bridge unlocked**: `WordWrapping + TextToGraphics` measured with the headless
  `truetype_measure_text` (= `pdf_measure_text`, the default `run_example` uses) → output is
  an `RGraphicsCanvas` (`<: GraphicsDocument`), so `<doc> → graphics` entries are
  `run_example`-able (SDL) and `<doc> → text` entries are `run_console_example`-able.
  **Not yet loaded through `using ProjecturedExample`** — that + `catalog()`/`test_catalog()`
  is an external-terminal check (beyond the light path safe to run here).
- [ ] **Phase 1 — element-domain annotation (mechanism under review).** Original plan:
  widen `@document` CellVector detection; emit `document_field_types`; annotate Json
  container fields; `minimal` fills one child. **Blocked/revise**: `CellVector` is already
  kind-parametric (see Implementation notes) and `@document` is a fatal-precompile-risk
  surface mid cell-kind review — decide the metadata mechanism with the user first.
  Verify `test_cell()` + Json doc/printer tests green.
- [ ] **Phase 2 — wire real testers + run-as-example.** `test_printer`/`reader`/`repl`
  over `filter(applies, catalog())`; `text_navigation`/`typein` over the `:text` subset;
  `run_example` over `filter(runnable, catalog())`, confirm they open. Confirm the
  `test_repl` terminal requirement.
- [ ] **Phase 3 — broaden & enrich (defer).** More domains as bridge edges/annotations;
  reconcile `AtomicFixture` (compose `Example`; migrate the 7 json fixtures — see
  "Reconciling `AtomicFixture`"); hand-woven combinator fixtures (the generic-`doc`
  residue discovery skips); decide whether `test_catalog` becomes a documented default.

## Risks / decisions

- **`CellVector{T}` is metadata, not a real parametric type** (recommended). Records
  your intent faithfully (`Any` at runtime), avoids the `IFoo` runtime-invariant and
  avoids teaching `@document` to define parametric structs. The heavier alternative —
  make `CellVector` genuinely parametric and thread `T` through construction — is
  recorded here as explicitly *not needed*.
- **`@document` change is the riskiest touch.** Isolate Phase 1; verify narrowly.
- **Heavy Julia runs are the user's to run externally** (precompile/full stack crashes
  the editor host). Verify via `test_cell()` and targeted document/printer tests.
- **Fidelity vs. the real pipeline.** An atomic stage tested in isolation can pass while
  failing in a full composition; the existing complex examples stay as the integration
  gate. This catalog is the fast, additive signal, not the sole one.
- **Output types are not static** (confirmed: neither printer nor reader signature
  carries them; the reactive layer erases to `Cell`/`Any`). The projection graph
  therefore resolves edges by **run-and-inspect** on minimal documents, or from the small
  runnable bridge registry — never from the method table alone. A bare stage whose output
  isn't inspected stays `:abstract` (still fine — it feeds the domain-agnostic tests and
  is simply not runnable).
```
