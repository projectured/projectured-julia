# Kind-parameterized documents: ReactiveCell / MutableCell / ImmutableCell

Status: **pending** (design agreed, not started)

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

- [ ] Refactor the template machinery to **build the selection cell first and pass it
      into the node constructor** (construction-time sharing already works — the
      auto-wrapping inner ctor accepts Cells). No node may be retargeted after `new`.
- [ ] Verify on the current architecture (no other changes):
      `test_printer(json_example)`, `test_repl(json_example)`, `test_json_to_syntax()`,
      one template-heavy domain (`test_ini()` or similar).

This lands independently and is valuable on its own (removes hidden mutation).

## Phase 1 — Cell kinds in the reactive layer

In `package/kernel/src/reactive/Reactive.jl` (ReactiveModule):

- [ ] `abstract type AbstractCell{T} end` with the shared read protocol `c[]`.
- [ ] `ReactiveCell{T} <: AbstractCell{T}`: rename + parameterize today's `Cell`.
      `value::T` uses **incomplete initialization** for computed cells (`new{T}()`,
      guarded by `valid`), replacing today's `value = nothing` placeholder.
      `deps`/`dependents` become `Set{ReactiveCell}` (abstract-element set; elements
      are heap references either way — negligible).
- [ ] `MutableCell{T} <: AbstractCell{T}`: `c[]` / `c[] = v`, no bookkeeping.
- [ ] `ImmutableCell{T} <: AbstractCell{T}`: `c[]` only (no `setindex!` method).
- [ ] `setfn!`/`setval!` remain `ReactiveCell`-only.
- [ ] **Compatibility alias:** `const Cell = ReactiveCell` (UnionAll) so `x isa Cell`
      and `Cell(v)` (→ `ReactiveCell{Any}(v)`) keep working everywhere; the `@document`
      macro will construct `ReactiveCell{DeclaredFieldType}` where a type is declared.
- [ ] Test: `test_cell()` extended with MutableCell/ImmutableCell protocol cases
      (read, write, write-to-immutable errors, no dependency registration from
      reading M/I cells inside a thunk).

## Phase 2 — Review gate: three-kind demo with tests and measurements

A **hand-written** vertical slice (no `@document` changes yet — the parametric stem,
aliases, and ctors are written out by hand exactly as the macro will emit them), so
the design is validated and measured *before* the invasive macro rewrite. Small
enough to run as a light driver in-editor; benchmarks user-run externally if needed.

- [ ] A tiny demo document type (2–3 fields, one child slot — e.g. a labeled pair)
      in the new parametric form, with `RDemo` / `IDemo` / `MDemo` aliases.
- [ ] One simple kind-generic projection over it (demo → text via `getproperty`
      only), demonstrating that a single printer body serves all three kinds, plus
      one **boundary-cell** case: an R parent holding an I subtree as one value.
- [ ] Correctness tests: identical print output across R/I/M; write-through works
      for R and M; writing an ImmutableCell field throws; reactive invalidation
      propagates for R; mutating M does **not** invalidate (by design).
- [ ] Measurements, tabulated for review:
      - construction + field-read + print-pass timings and `@allocated` for each
        kind, against today's untyped `Cell` as baseline;
      - type stability via `Test.@inferred` on field reads per kind;
      - `perf_counters` read/write counts for the reactive kind.
- [ ] **Stop here for user review** of the demo code and the numbers. Phase 3 does
      not start until the slice is approved (this is the cheap moment to change the
      encoding).

## Phase 3 — `@document` rewrite

In `package/kernel/src/common/Document.jl`:

- [ ] Emit the **immutable parametric stem**: one `C_i <: AbstractCell{T_i}` parameter
      per field (`AbstractCell` unconstrained when no type is declared).
- [ ] Emit the three concrete aliases `RFoo` / `IFoo` / `MFoo`. The old standalone
      `IFoo` struct + snapshot/hydrate ctor pair is **deleted** (it was ~unused; the
      alias takes over the name and the exports in `Json.jl` / `Text.jl` still work).
- [ ] Bare-name ctor family (auto-wrapping positional, kwctors, Rule Y, Rule C —
      **keep the `req ≥ 1` guard**) targets the **reactive kind**. `IFoo`/`MFoo` get
      the auto-wrapping positional + keyword ctors only.
- [ ] One `getproperty` (`getfield(obj, f)[]`) and one `setproperty!`
      (`getfield(obj, f)[] = v`) for the UnionAll — kind dispatch happens in the cell.
- [ ] `cell_kind(doc)` trait; `rekind(K, doc)` generic walk; `snapshot`/`hydrate`
      conveniences.
- [ ] Adapt `copy_document` (reconstruct with fresh cells of the *same kind*).
- [ ] `@forward` / `@forward_vector` / `@forward_map` read via `getproperty` — verify
      unchanged.
- [ ] Update `documentation/macros.md` (the "Why every field is a Cell" section gains
      the kind story; the I-struct section is rewritten).
- [ ] Test: `test_json()` first, then `test_printers()` sweep **run by the user in an
      external terminal** (full precompile is too heavy for the editor host).

## Phase 4 — Collection kinds

- [ ] Parameterize `CellVector` by cell kind: elements stored as `Vector{C}` with
      aliases mirroring the documents. R = today's semantics; M = same minus
      bookkeeping; I = frozen (mutating protocol methods error).
- [ ] Rule C in `@document` keeps emitting element-accepting sugar for the bare
      (reactive) name only.
- [ ] Test: `test_printer(json_example)` (arrays/objects), collection unit tests.

## Phase 5 — Identity, references, serialization audit

- [ ] **objectid audit:** the template reuse maps key children by
      `(objectid(node), i)`; with immutable wrappers objectid is content-derived
      (from the cell pointers). Confirm reuse still discriminates correctly (two
      egal nodes are genuinely interchangeable) and that nothing relied on
      allocation-distinct wrappers.
- [ ] **Type checkpoints:** `annotate_reference_types` / `fold_reference_types`
      record the UnionAll (`Base.typename(typeof(node)).wrapper`); strict path `==`
      then stays kind-agnostic. Audit `typeof(x) === SomeDoc` comparisons anywhere
      in kernel/domain.
- [ ] **Serialization:** check the `.pdoc` binary snapshot path
      (`domain/src/serializer/DocumentFile.jl`) with parametric type names; decide
      whether snapshots should always be written as the I kind (natural fit) and
      hydrated on load.
- [ ] Test: `test_reader(json_example)`, `test_text_navigation(json_example)`,
      selection round-trip tests; serializer round-trip test.

## Phase 6 — Pure batch printer (payoff #1)

A second interpreter of `@projection_template`: same builder spec, but

- input: any kind (reads are kind-generic), output: **I-kind** nodes,
- **no iomaps** (nothing to map back — no reader, no selection forwarding in v1),
- no reactive wiring (plain recursion instead of computed cells).

- [ ] `projection_print_pure(p, doc) :: I-kind output` derived from the template spec
      (`rule_print`'s sibling). Hand-written projections get the **total fallback**:
      `snapshot(print(hydrate(doc)))` — slow but correct, so the pure pipeline works
      end-to-end from day one; convert stages to the fast path where profiles say so.
- [ ] Wire into the export paths (`write_image` / `write_pdf` / text serialization)
      behind a flag; benchmark against the reactive printer using the
      `perf_counters` machinery (`reactive/PerformanceCounter.jl`).
- [ ] Test: pure-print output equals reactive-print output (structural equality on
      snapshots) for 2–3 example documents per pipeline.

## Phase 7 — M→R shadow sync (payoff #2: simulation state)

The double-buffer pattern: a simulator mutates M-kind state freely (zero reactive
overhead per event, no observable intermediate states); at pause points a reconciler
diff-copies into a shadow R-kind tree that feeds the normal projection pipeline.

- [ ] `sync_document!(shadow::R-kind, source::M-kind)`: generic fieldwise walk,
      writing a shadow cell **only when the value changed** (minimal invalidation
      set). Shadow correspondence held in an `IdDict` keyed by the source node's
      cells (MutableCell boxes are identity-stable), so keyed reconciliation
      survives vector shifts (a dequeue does not rewrite every cell).
- [ ] Vector reconciliation: match by source-element identity first, index second.
- [ ] A small demo domain (toy discrete-event queue sim) under `package/example/`
      exercising mutate → sync → incremental reprint.
- [ ] Test: sync writes exactly the changed cells (assert via `perf_counters`
      write counts); repeated sync with no changes is a no-op.

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
