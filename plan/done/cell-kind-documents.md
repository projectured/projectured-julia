# Kind-parameterized documents: ReactiveCell / MutableCell / ImmutableCell

Status: **implemented** on branch `worktree-cell-kind-documents` — Phases 0–7 done
(Phase 6 descoped to fallback-only; a few sub-items deferred with rationale, and
the user-run test sweeps still owed). Not yet merged; heavy `test_*` verification
must run in an external terminal. Commit trail: 6630178 (P0) · a28b1bb (P1) ·
b5a1eca + 8267a0d (P2 review gate) · fc34192 (P3) · a844dac (P4) · fb8f264 (P5) ·
36bcb9f (P6) · 43efd21 (P7).

## Goal

Replace the current two-variant `@document` output (mutable Cell-field struct `Foo` +
nearly-unused immutable sibling `IFoo`) with **one immutable, type-parameterized stem
struct per document type**, where the *cell kind in the fields* decides the behavior:

- `ReactiveCell{T}` — today's `Cell` semantics, but typed: value + thunk + deps/dependents,
  dependency registration on read, invalidation on write.
- `MutableCell{T}` — a plain mutable box: read/write, **no** reactive bookkeeping.
  Reading it inside a reactive thunk registers *nothing*; mutating it invalidates
  *nothing*. That is the point (see the simulation use case).
- `ImmutableCell{T}` — a plain immutable wrapper: read-only. Zero-cost: an immutable
  struct with a concrete field inlines into its parent, so the all-immutable
  instantiation is layout-identical to a plain Julia struct.

One `@document struct JsonString … end` then yields (sketch):

```julia
struct JsonString{C1 <: AbstractCell{String}, C2 <: AbstractCell{SelT}} <: JsonDocument
    value::C1
    selection::C2
end
const RJsonString = JsonString{ReactiveCell{String},  ReactiveCell{SelT}}
const IJsonString = JsonString{ImmutableCell{String}, ImmutableCell{SelT}}
const MJsonString = JsonString{MutableCell{String},   MutableCell{SelT}}
```

`JsonString(...)` (bare name) keeps constructing the reactive kind, so existing
construction sites do not change. `::JsonString` in a signature is the UnionAll and
matches **all** kinds — the bare name *is* the abstract base, for free.

## Why this design (decisions + rationale from the design discussion)

1. **Unified parametric stem beats three generated structs (RStem/IStem/MStem).**
   One struct definition ≈ ⅓ the codegen; one `getproperty`/`setproperty!` covers all
   kinds so every existing printer/reader/hand-written function is kind-generic with
   zero changes; no abstract-type + constructor-forwarding migration trick needed.
2. **The stem must be immutable — this is forced, not stylistic.** Julia cannot
   parameterize mutability of a struct. All mutability lives in the cells.
3. **Typed cells fix a system-wide performance problem.** Today's `Cell`
   (`kernel/src/reactive/Reactive.jl`) is `value::Any` + two `Set{Cell}`s; every field
   read in the editor is dynamically typed. `ReactiveCell{T}` makes even the reactive
   kind type-stable; `ImmutableCell{T}` makes the immutable kind allocation-free.
4. **Granularity is a per-node knob.** A `Document`-typed child slot can hold an
   immutable subtree under a reactive parent: the reactive graph sees the immutable
   part as one value in one boundary cell — upstream change regenerates it wholesale,
   downstream invalidates normally. Rule of thumb:
   **R = anything on the edit path; I = derived/display/export content; M = anything on
   the high-frequency mutation path** (with a sync step into R, below).
5. **Interaction boundary rule.** Nothing inside an immutable region can receive a
   caret or be edited in place; `set_selection!` into an I-subtree is a `MethodError`
   by design. Selection/interaction stops at the boundary node (whole-element `∅`
   selection at best).
6. **M-kind boxing cost accepted.** A dedicated `mutable struct MFoo` would inline
   fields in one heap object; `Foo{MutableCell…}` pays one box + one pointer hop per
   field. Accepted because container fields (queues = `Vector`) are heap references
   anyway and are mutated *through* the cell, not by swapping it. Escape hatch if a
   profile disagrees: hottest sim structs stay hand-written plain structs and only the
   sync step touches the document mirror.
7. **No leading kind type-parameter.** Per-field parameters (required, since a field
   cannot be typed `K{String}` from a kind parameter) + the three concrete aliases +
   a `cell_kind(doc)` trait function cover dispatch needs. A redundant leading
   parameter would complicate every alias and the macro.
8. **Conversion is a function, not constructors.** `rekind(K, doc)` (generic recursive
   fieldwise walk) with conveniences `snapshot(doc) = rekind(ImmutableCell, doc)` and
   `hydrate(doc) = rekind(ReactiveCell, doc)`. Constructor overloads like
   `RFoo(ifoo)` are avoided deliberately — the ctor families (kwctors, Rule Y, Rule C)
   are already a method-collision minefield (see the Rule Y `req ≥ 1` guard).
9. **Identity moves into the cells.** `===`/`objectid` of an immutable wrapper derives
   from its fields (the cell boxes), not from a wrapper allocation. Rebuilding a
   wrapper around the same cells yields an egal node — arguably better (identity lives
   where the state lives), but the `objectid`-keyed iomap reuse must be audited
   (Phase 5).
10. **Reference type checkpoints record the UnionAll.** `annotate_reference_types`
    currently records `typeof(node)` (would be a kind-specific concrete type).
    Recording `Base.typename(T).wrapper` (i.e. `JsonString`) makes checkpoints and
    strict path `==` kind-agnostic; the `isa` match rule already tolerates supertypes.
11. **Per-field kind mixing is expressible but not blessed in v1.** The per-field
    parameters make mixed instantiations valid (`JsonString{ImmutableCell{String},
    ReactiveCell{SelT}}`), and the auto-wrapping ctor produces them ad hoc when
    explicit cells are passed. The convenience surface (aliases, ctor families,
    `cell_kind`, `rekind`) stays per-node uniform, because a reactive thunk reading a
    MutableCell field registers no dependency — free mixing invites silent-staleness
    bugs. Named exception worth designing later: **immutable content + reactive
    selection** (all fields ImmutableCell except `selection::ReactiveCell`), which
    relaxes the interaction boundary rule to *selectable but not editable* — right
    for generated/derived content the user should still click and copy from.

## Non-goals / out of scope

- `@projection` and `@iomap` structs stay reactive-only mutable structs (they are
  editor machinery, never immutable/mutable-kind data). They benefit transparently
  from the `Cell = ReactiveCell` alias, nothing more.
- No change to projection semantics, reference model, or the operation system.

---

## Phase 0 — Prerequisite: remove post-construction cell swapping

The only reason `@document` structs are mutable today is swapping a field's Cell
*object* after construction. All such sites are in
`package/domain/src/projection/ProjectionTemplate.jl` (~10 × `setfield!(out|child|leaf,
:selection, …)`), none in domain code or hand-written printers.

- [x] Refactor the template machinery to **build the selection cell first and pass it
      into the node constructor** (construction-time sharing already works — the
      auto-wrapping inner ctor accepts Cells). No node may be retargeted after `new`.
      *Done via a `_with_selection(node, sel)` helper that rebuilds the node once,
      reusing every other field's Cell object; `_atomic_print` switched to the
      deferred-iomap pattern the other shapes already used; `_inline_print` rebuilds
      its bound leaf inside the children thunk (fresh each recompute, so safe).*
- [x] Verified with a light driver (JSON → Syntax → Text, domain-only): content
      flows, a caret at `entries[1].value.value{3}` forward-maps to
      `::TextText.elements[10].content::String{3}`, reactive value edits and
      structural (array-append) edits propagate.
- [ ] **User (external terminal):** `test_printer(json_example)`,
      `test_repl(json_example)`, `test_json_to_syntax()`, `test_ini()` — too heavy
      for the editor host.

This lands independently and is valuable on its own (removes hidden mutation).

## Phase 1 — Cell kinds in the reactive layer

In `package/kernel/src/reactive/Reactive.jl` (ReactiveModule):

- [x] `abstract type AbstractCell{T} end` with the shared read protocol `c[]`.
- [x] `ReactiveCell{T} <: AbstractCell{T}`: rename + parameterize today's `Cell`.
      `value::T` uses **incomplete initialization** for computed cells (`new{T}()`,
      guarded by `valid`), replacing today's `value = nothing` placeholder.
      `deps`/`dependents` become `Set{ReactiveCell}`. *Also: `set_function!` no longer
      nulls the value slot (a typed cell can't hold `nothing`) — the stale value
      stays cached until the first read, except when `nothing isa T`.*
- [x] `MutableCell{T} <: AbstractCell{T}`: `c[]` / `c[] = v`, no bookkeeping.
      *Lesson: do NOT hand-write the `MutableCell(v)`/`ImmutableCell(v)` convenience
      ctors — Julia auto-generates the param-inferring ctor from the field, and the
      duplicate is a fatal precompile method-overwrite.*
- [x] `ImmutableCell{T} <: AbstractCell{T}`: `c[]` only (no `setindex!` method).
- [x] `set_function!`/`set_value!` remain `ReactiveCell`-only; `peek`/`is_up_to_date` get
      `AbstractCell` fallbacks (plain read / always `true`).
- [x] **Compatibility alias — REVISED in Phase 3:** `const Cell =
      ReactiveCell{Any}` (**concrete**, not the UnionAll originally planned).
      The UnionAll alias made every `Vector{Cell}`, `Set{Cell}` and `::Cell`
      machinery-struct field abstract-typed — the JSON bench showed real-document
      builds 2.5× slower until the alias went concrete (after which builds beat
      the pre-parameterization baseline: 15 ms vs 24 ms). Code that means "a cell
      of any kind" now tests `isa AbstractCell` (swept: Searching, Reference,
      Sequential, Operation, Collection `_wrap_cell`); `isa ReactiveCell` means
      "reactive of any value type".
      *Fallout handled: `BinarySerialization` tags cells with their concrete type
      (`serialize_type(s, typeof(c))`, hooks on `ReactiveCell`) and the `.pdoc`
      format version bumped 1 → 2 so old files are rejected cleanly. M/I cells
      count nothing in `get_performance_counters` — their reads are meant to cost a pointer
      load (documented in the module).*
- [x] Test: `test_cell()` extended with typed-ReactiveCell / MutableCell /
      ImmutableCell testsets (typed reads `@inferred`, conversion-on-write,
      write-to-immutable `MethodError`, no dependency registration from reading M
      cells inside a thunk). Verified green via a light driver (24/24) — the
      `test_cell()` form itself is **user-run** (ProjecturedTest is too heavy here).

## Phase 2 — Review gate: three-kind demo with tests and measurements

A **hand-written** vertical slice (no `@document` changes yet — the parametric stem,
aliases, and ctors are written out by hand exactly as the macro will emit them), so
the design is validated and measured *before* the invasive macro rewrite. Small
enough to run as a light driver in-editor; benchmarks user-run externally if needed.

- [x] A tiny demo document type in the new parametric form, with
      `RDemoItem` / `IDemoItem` / `MDemoItem` aliases:
      **`package/kernel/demo/CellKindDemo.jl`** (standalone,
      `julia --project=. package/kernel/demo/CellKindDemo.jl`).
- [x] One simple kind-generic projection over it (single printer body serves all
      three kinds via one uniform `getproperty`), a **boundary-cell** case (R parent
      holding an I subtree as one value; subtree swap invalidates the parent render),
      a **mixed-kind** node (decision 11: immutable content + reactive selection),
      and the generic `rekind`/`snapshot`/`hydrate` walk with a `cell_kind` trait.
- [x] Correctness tests — 20/20 green: identical print output across R/I/M;
      write-through for R and M; `ImmutableCell` write throws; reactive invalidation
      propagates for R; mutating M does **not** invalidate; I→R hydration editable;
      `@inferred` type-stable reads on the I kind.
- [x] Measurements (chain of 10 000 nodes, min of 7 runs, Julia 1.11 worktree):

      | kind                        | build ms | build MB | read ms | print ms |
      |-----------------------------|----------|----------|---------|----------|
      | today's `Cell` struct (base)|    1.32  |   11.8   |  0.47   |   1.91   |
      | `ReactiveCell{T}` (typed)   |    1.48  |   11.7   |  0.53   |   1.40   |
      | `MutableCell{T}`            |    0.81  |    4.0   |  0.40   |   1.35   |
      | `ImmutableCell{T}`          |    0.75  |    3.3   |  0.72   |   1.35   |

      `get_performance_counters`, one print pass over 10 000 nodes: reactive kind
      **reads=30 000**, M kind **reads=0** (no bookkeeping, as designed).

      Reading of the numbers: build is ~1.7–1.8× faster and ~3× lighter for M/I
      (no `deps`/`dependents` Sets); print is ~29 % faster for I/M. The *walk*
      column is dispatch-bound (children are behind the abstract `Document` union,
      so every step is a dynamic dispatch for every kind — realistic for document
      trees); the type-stability win shows *within* a node (`@inferred` passes),
      and the bigger printing payoff is expected from skipping iomap construction
      and reactive wiring in the pure printer (Phase 6), not from raw field reads.
      Measurement lesson: the first print column was swamped by an O(n²)
      `"  "^depth` indentation artifact — bench harnesses must keep per-node work
      O(1) or the kind differences drown.
- [x] **Large-JSON benchmark** (`package/domain/demo/CellKindJsonBench.jl`): a
      hand-written parametric mirror of the JSON documents (faithful declared
      field types, loose bounds) vs a legacy-emission mirror vs the real
      `JsonObject` stack, all on one 57 489-node tree (depth 4, fanout 16,
      0.52 MB printed), printers structurally identical, outputs asserted equal:

      | variant                      | build ms | build MB | read ms | print ms |
      |------------------------------|----------|----------|---------|----------|
      | real `JsonObject` (today)    |   23.7   |   54.5   |  12.4   |   8.2    |
      | legacy mirror (mut + `Cell`) |    6.4   |   45.5   |   9.7   |  16.6    |
      | mirror `ReactiveCell{T}`     |    9.3   |   46.2   |  11.1   |   8.3    |
      | mirror `MutableCell{T}`      |    3.1   |   14.0   |   8.6   |   4.1    |
      | mirror `ImmutableCell{T}`    |    2.7   |   11.4   |   6.1   |   3.8    |

      One print pass: real **151 170** tracked reads, mirror-R **80 913** (the
      delta ≈ `CellVector`'s per-element slot cells, which the mirrors don't have
      — collection kinds are Phase 4), M/I **0**. Takeaways: I/M build ~8× faster
      and ~4× lighter than the real stack; print ~2× faster than real and R;
      the R kind's win over the legacy mirror shows in print (8.3 vs 16.6 —
      typed cell reads make downstream dispatch inferable). Bench lesson recorded
      in the file: the kind must be a *static* `::Type{K}` parameter in factories
      — a runtime `K{String}` type-application per node dominated the first build
      measurement (~30 ms instead of ~9/3 ms); the macro's emitted ctors use
      concrete cell types, which is what the static parameter models.
- [ ] **Stop here for user review** of the demo code and the numbers. Phase 3 does
      not start until the slice is approved (this is the cheap moment to change the
      encoding). **⇐ CURRENT STATE: awaiting review.** Additional finding for the
      review: strict per-field bounds (`C_i <: AbstractCell{T_i}`) are incompatible
      with ad-hoc untyped `Cell(x)` cells (invariance), so Phase 3 will emit loose
      bounds — see the note in Phase 3.

## Phase 3 — `@document` rewrite

In `package/kernel/src/common/Document.jl`:

- [x] Emit the **immutable parametric stem**: one cell type-parameter per field,
      loose bounds (`C_i <: AbstractCell`) per the Phase 2 finding. Cell types are
      spliced as *objects*, so caller modules need no new imports.
- [x] Emit the three concrete aliases `RFoo` / `IFoo` / `MFoo`; **the macro exports
      them itself** (modules' explicit I-name exports remain harmless duplicates).
      The old standalone `IFoo` struct + snapshot/hydrate ctor pair is deleted;
      `snapshot(foo)` replaces the `IFoo(foo)` ctor form.
      **Decision (deviation from the Phase 2 demo): the bare ctor wraps raw values
      in `ReactiveCell{Any}` — NOT `ReactiveCell{T_declared}` — and `RFoo` is the
      all-`Any` instantiation.** Three reasons: `@projection_template` builders
      store `bound(…)` markers in String-typed fields before stripping them;
      `nothing` defaults in fields whose declared type doesn't admit `nothing`;
      exact behavioral parity for the migration. The typed-reactive win the demo
      measured (print 2× vs untyped) is deferred to a later tightening phase.
      `IFoo`/`MFoo` ctors DO use typed cells (markers never flow there).
- [x] Bare-name ctor family (auto-wrapping positional, kwctors, Rule Y, Rule C —
      `req ≥ 1` guard kept) targets the reactive kind; `IFoo`/`MFoo` get full-arity
      value ctors + keyword ctors. **No parametric inner ctor** (it is dispatch-
      ambiguous with the alias value ctors for all-cell args); reconstruction sites
      call the UnionAll via `Base.typename(T).wrapper` instead (`copy_document`,
      `rekind`, ProjectionTemplate's `_with_selection`).
      *Perf lesson (caught by the JSON bench): `new{typeof(w)…}` with runtime type
      params made real-JSON builds 2.5× slower; the inner ctor now has two
      constant-parameter fast paths (all args `ReactiveCell{Any}` / no arg a cell),
      leaving the dynamic path to kind ctors and `rekind` only.*
- [x] One `getproperty` (`getfield(obj, f)[]`) and one `setproperty!`
      (`getfield(obj, f)[] = v`) for the UnionAll — kind dispatch happens in the cell.
- [x] `cell_kind(doc)` trait; `rekind(K, doc)` generic walk (typed I/M targets via a
      macro-emitted `_declared_value_types` method — added through
      `(::typeof(f))(…)`, since a spliced function object is not a valid method
      name); `snapshot`/`hydrate` conveniences. Verified on real JSON documents
      (snapshot → `IJsonObject` with `ImmutableCell{String}` leaves, hydrate back,
      M-kind write-through).
- [x] Adapt `copy_document` (fresh cells of the same kind and value type, via
      `_same_cell`; constructs through the UnionAll).
- [x] `@forward` / `@forward_vector` / `@forward_map` unchanged (exercised via
      `doc["name"]` paths in the drivers). `CellVector` is itself `@document`, so it
      became parametric automatically; `CollectionModule` adds the `rekind` method
      (elements rekinded; slot cells stay reactive — Phase 4 stopgap).
- [x] UnionAll fallout: `Pair{DataType,Any}` literals → `Pair{Type,Any}` (9 files,
      domain/example/test); kernel's `TypeDispatchingProjection` already stored
      `Pair{Type,Any}` and matches via `isa` — no change needed.
- [x] Update `documentation/macros.md` (the `@document` section rewritten around
      the kind-parameterized stem).
- [x] Light verification green: kernel sanity driver (32/32 — ctors, aliases,
      kinds, rekind, Rule Y/C, mixed nodes), domain kind driver (13/13 on real
      JSON), JSON pipeline driver (selection forward-map + reactive/structural
      edits), cell driver, both demos. **Precompile: kernel 2.3 s + domain 8.0 s
      (~11 s total vs ~10 s baseline, ≈ +10%)** — within budget.
- [x] **Post-Phase-3 JSON bench** (57 489-node tree, real documents now on the
      parametric stem): build 15.2 ms (**was 23.7 pre-parameterization** — the
      constant-parameter ctor fast paths beat the old mutable ctor), read 9.7 ms
      (was 12.4), print ≈ baseline (8–10 ms, run-noisy). Mirror columns unchanged.
      Bench note: the real factory now uses closures — a document *name* is a
      UnionAll, and storing it as a NamedTuple value made every factory call a
      dynamic dispatch, which real code (static ctor call sites) does not do.
- [ ] **User (external terminal):** `test_json()` first, then a `test_printers()`
      sweep; also `test_cell()` and one reader/repl example — too heavy here.

## Phase 4 — Collection kinds

- [x] `CellVector` kinds — **implemented as one type with a per-kind storage
      convention**, not separate element vectors: the reactive kind stores
      `Vector{Cell}` slot cells (unchanged semantics); the immutable/mutable kinds
      store a plain value `Vector` (no slot cells — nothing for them to do without
      reactivity). Declared `elements` type loosened to `Vector` so the macro
      I/M aliases are right; `ICellVector(items)` / `MCellVector(items)` value
      ctors added. `rekind` builds the target convention, so `snapshot(json)` now
      produces genuinely frozen collections.
      **Perf lesson: protocol methods dispatch on the struct parameter
      (`const RCV = CellVector{<:ReactiveCell}`), not on runtime storage checks —
      the branching version cost the reactive read path ~2× (real-JSON read went
      1.07× → 2.5× of the mirror); parameter dispatch restored parity (1.12×).**
      Frozen means untouched: mutators guard via `_mutable_plain` *before* touching
      the backing vector, so a failed mutation cannot leave a half-applied change.
- [x] Rule C in `@document` keeps emitting element-accepting sugar for the bare
      (reactive) name only (unchanged).
- [ ] `CellMatrix` / `CellTable` / `ListNode` stay reactive-only for now — their
      I/M aliases exist (macro) but the plain-storage protocol is not implemented;
      `rekind` through them shares slot cells. Do when a consumer needs them.
- [x] Verified: I-kind collections read/iterate, refuse mutation atomically;
      M-kind write-through; hydrate returns reactive collections
      (phase-4 driver testset, 11/11). Bench read/print at parity; the bench's
      build column is GC-noisy (15–60 ms run-to-run for identical code) — ratios
      within one run are the usable signal.
- [ ] **User (external terminal):** `test_printer(json_example)`, collection unit
      tests.

## Phase 5 — Identity, references, serialization audit

- [x] **objectid audit — no change needed.** `objectid` of an immutable stem is
      content-derived from its fields, but the fields are `ReactiveCell` objects
      (mutable → identity-hashed) that are never swapped after construction, so a
      reactive node's `objectid` is **stable across reprints** exactly as the old
      mutable struct's was. Verified: mutating a leaf's value, and a structural
      array push, both leave surviving nodes' objectids unchanged. Two egal nodes
      (same cells) share an objectid — which is correct, they are interchangeable —
      and no distinct input elements share cells, so the `(objectid, i)`
      reconciliation cache cannot collide.
- [x] **Type checkpoints — record the UnionAll.** `annotate_reference_types` now
      records `Base.typename(typeof(node)).wrapper` via a `_node_type` helper
      (`fold_reference_types` was already type-source-agnostic — it folds whatever
      the `@reference` builder emits, which is bare names = wrappers). The
      ProjectionTemplate wirings likewise record `_dtype(doc)`/`_dtype(out)` (the
      wrapper) at all 7 construction sites, so the forward/backward-mapped
      selection paths carry bare names too. Result: strict path `==` and the
      `document isa path.type` match rule are kind-agnostic — a path annotated on
      a reactive node validates against its immutable snapshot, and equals a path
      annotated on the snapshot. No `typeof(x) === SomeDoc` comparisons exist in
      kernel/domain (grep clean).
- [x] **Serialization — round-trips.** The serializer tags cells with their
      concrete `ReactiveCell{T}` (Phase 1) and the loader rebuilds through the
      auto-wrapping ctor, so a saved reactive document reloads as `RJsonObject`
      with values and selection intact (`.pdoc` version 2 already rejects v1).
      Deferred (not needed for correctness): writing snapshots as the I kind.
- [x] Verified via the phase-5 audit driver (13/13): objectid stability,
      kind-agnostic annotate/validate/equal, evaluate through both kinds,
      save/load round-trip, reactive reprint after edit.
- [ ] **User (external terminal):** `test_reader(json_example)`,
      `test_text_navigation(json_example)`, selection round-trip + serializer tests.

## Phase 6 — Pure batch printer (payoff #1) — **DESCOPED to fallback-only**

**Finding that forced the descope:** the plan assumed most projections are
`@projection_template`-based, so one template interpreter would cover the pipeline.
It is not: **only 7 projections use the macro** — the domain→syntax *entry* stages
(`JsonToSyntax`, `XmlToSyntax`, `SqlToSyntax`, `JuliaToSyntax`, `MarkdownToSyntax`,
`YamlToSyntax`, `BookToSyntax`). Everything downstream — `SyntaxToText`,
`…ToWidget`, `…ToGraphics` — is **hand-written**, and those are the *heavy* render
stages. A template-only fast interpreter would accelerate the cheap entry hop while
the heavy stages fell back to snapshot-of-reactive (reactive build **+** a copy —
*slower* than plain reactive). So the fast interpreter can't show an end-to-end win
on its own; the real pure-printer payoff is gated on hand-writing pure methods for
the render-layer projections, which is a separate, larger, per-projection
investment to make deliberately. Descoped by decision (user, 2026-07-03).

**Delivered (fallback-only) — the end-to-end plumbing:**

- [x] `pure_print_document(projection, recursion, input, ctx)` generic function
      (api stub in `ProjectionApiModule`) + `pure_print_child`; `pure_print(p,
      doc)` entry (`ProjectionModule`).
- [x] **Total fallback** `pure_print_document(p::Projection, …) =
      snapshot(force(print_document(p,…).output))` — covers *every* projection
      correctly today (~100+), no per-projection work. Produces immutable output.
- [x] Three higher-order threaders so a *pipeline* is pure end-to-end: Sequential
      (thread stages), Recursive (delegate with self as recursion), TypeDispatching
      (first-match dispatch). Each 3–6 lines.
- [x] Verified: `pure_print(json→syntax→text)` yields an `ImmutableCell`-kind
      `TextText` whose visible text equals the reactive printer's, and refuses
      mutation; a template stage alone round-trips; an immutable syntax tree feeds a
      reactive downstream stage unchanged (reads are kind-generic).
- [x] **`rekind`/`snapshot` totality fix (load-bearing):** the reactive kind stores
      every field as `Any`, so a nominally `StyleColor` field can hold `nothing`
      (an unset optional). `rekind` to a typed I/M cell now uses the declared type
      only when the value conforms, else the value's own type (`_rekind_value_type`)
      — otherwise `ImmutableCell{StyleColor}(nothing)` was unconstructable and
      `snapshot` crashed on any real Text/Graphics tree.
- [ ] **NOT done (deferred):** the template `_pure_rule_print` fast interpreter; the
      macro emitting a pure method; wiring into `write_image`/`write_pdf` behind a
      flag; per-projection pure methods for the render layers. Revisit only with a
      profile that justifies the per-projection work.

## Phase 7 — M→R shadow sync (payoff #2: simulation state)

The double-buffer pattern: a simulator mutates M-kind state freely (zero reactive
overhead per event, no observable intermediate states); at pause points a reconciler
diff-copies into a shadow R-kind tree that feeds the normal projection pipeline.

- [x] `sync_document!(shadow, source)` (`DocumentModule`): generic fieldwise walk —
      a child document synced in place when same-type (`_same_wrapper`) else
      `hydrate`d fresh; a leaf field written **only on `!isequal`**. Writes exactly
      the cells that changed, so the reactive view sees a minimal invalidation set.
- [x] `CellVector` reconciler (`CollectionModule`): positional — same-type slot
      synced in place, changed slot rewritten, longer source appends (fires the
      structure cell once), shorter trims from the end.
- [x] Demo: `package/example/demo/CellKindSimDemo.jl` — a toy discrete-event queue
      sim mutating a `MutableCell`-kind `SimState` freely, a reactive shadow via
      `hydrate`, a computed "total work" view. 19/19. Measured:
      - reading the mutable sim inside a reactive thunk registers **nothing** — the
        view is unaffected until sync (the whole point of M-kind);
      - **4.0 shadow writes/sync** for ≤3 in-place `remaining` changes across a
        200-job queue (leaf-level "only updated if different"), and a no-change sync
        writes **0** and recomputes nothing (idempotent).
- [x] **Known limitation, measured not hidden:** positional CellVector matching
      rewrites the whole tail on a *front* dequeue (**50 writes** for a 50-job
      front pop), because every position's value shifts. The plan's identity-keyed
      refinement (a persisted `IdDict{source-elem ⇒ shadow-elem}`, keyed on the
      identity-stable `MutableCell` boxes) would make front shifts minimal too; it
      needs cross-sync state, so it is deferred until a front-heavy workload needs
      it. In-place updates, enqueue, and pop-from-end are already minimal.
- [x] Constructor footgun found + documented (not a regression): a bare 2-arg
      `CellVector(a, b)` resolves to the macro's 2-*field* inner ctor
      (`elements`, `selection`), not two elements. All real 2-arg call sites pass
      cells (fields) — correct; a 2-*element* vector needs `CellVector([a, b])`.
      Comment in `Collection.jl` corrected.

---

## Risks / open questions

- **Precompile weight:** per-field type parameters mean method specialization per
  instantiation at use sites. Only 3 uniform instantiations exist per type, but the
  sweep (283 types) needs a before/after precompile-time measurement (user-run,
  external terminal).
- **Ctor collisions:** the Rule Y/Rule C emission interacting with per-kind ctors —
  keep kind-specific families minimal (see decision 8); watch for the known
  method-overwrite failure mode.
- **Mixed-kind `==`:** structural equality across kinds (`RFoo(1) == IFoo(1)`?) —
  propose: yes, fieldwise through `getproperty`; decide when writing the generic `==`.
- **ImmutableCell{T} with abstract T** (e.g. `Union{Real,Nothing}` fields) loses the
  inline-storage win for those fields — fine, correctness unaffected.
- **Naming:** `rekind` / `snapshot` / `hydrate` final names TBD at implementation.
- **Selectable-but-immutable nodes** (decision 11's mixed exception): if adopted,
  `cell_kind(doc)` needs a per-field form (`cell_kind(doc, :field)`) and the I-kind
  alias definition must decide whether `selection` defaults to ReactiveCell.
