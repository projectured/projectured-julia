# Eliminate the Cell thunk trap — explicit `Computed` marker

**Status: done.** Design (option 1 of the 2026-08-03 discussion) approved by the user; implemented
2026-08-03 on `main` in projectured-julia and omnetpp-julia.

## Problem

`ReactiveCell{T}(f::Function)` decides *semantics* from the argument's runtime type: a
`Function` becomes the cell's thunk (a computed cell), anything else is stored as a value.
There is no way to say "this function is a value" at any of the generic construction seams,
because they all funnel into `Cell(x)`:

- the `@cell_struct`/`@document` autowrap inner constructor (`$a isa Cell ? $a : Cell($a)`,
  `cell/CellStruct.jl`) — behind every `@document` struct (~401 across the repos);
- `CellVector._wrap_cell` and the ~72 `Cell[Cell(x) for x in …]` comprehensions;
- operation replay (`base/main/operation/Operations.jl` insert!);
- `copy_cell_as(c::ReactiveCell{T}, v) = ReactiveCell{T}(v)` (`cell/CellDefaults.jl`) — a
  **live latent bug**: deep-copying a document whose cell legitimately holds a function value
  (Widget.jl `action`/`callback` fields, omnetpp `Optimization.jl` objective) silently converts
  it back into a thunk. The existing workarounds protect first construction only, not copies.

The Common Lisp original does not have this trap: `(as body)` constructs a distinct
`computed-state` struct and the slot machinery dispatches on `computed-state-p`, never on
`functionp` (`projectured-lisp/source/util/computed.lisp`). Computedness there is a marker
*type* created explicitly at the write site. The Julia port introduced the trap by replacing
that marker with runtime-type dispatch on `Function`. This plan restores the original design.

## Design (final state)

**Principle: a cell's constructor argument is always the value.** Computedness is expressed by
a distinct marker type, consumed at every cell ingestion point (construction and write).
Backward compatibility is explicitly not a goal.

New vocabulary, in a new file `cell/CellComputed.jl` (included between `CellInterface.jl` and
`ReactiveCell.jl`, since `ReactiveCell`'s inner constructor dispatches on it):

```julia
struct Computed
    thunk::Function
end
```

Deliberately **non-parametric** — see the runtime cost analysis.

The constructor/write surface after the change:

| spelling                                        | result                                             |
|-------------------------------------------------|----------------------------------------------------|
| `Cell(x)` / `ReactiveCell{T}(x)`                | value cell holding `x` — for *every* `x`, including `Function` and callable structs |
| `Cell(Computed(f))` / `ReactiveCell{T}(Computed(f))` | computed cell with thunk `f`                  |
| `ComputedCell(f)`                               | convenience ≡ `Cell(Computed(f))` (defined next to the `Cell` alias) |
| `c[] = v`                                       | value write (unchanged)                            |
| `c[] = Computed(f)`                             | ≡ `set_cell_function!(c, f)` — new bridge, so `doc.f = Computed(…)` works through the transparent `setproperty!` path too |
| `set_cell_function!(c, f)`                      | unchanged explicit primitive                       |
| `ImmutableCell(Computed(f))` / `MutableCell(Computed(f))` | clear `error(…)` — guards in `CellDefaults.jl`; a thunk needs a `ReactiveCell` |

**Deleted:** the `ReactiveCell{T}(f::Function)` thunk constructor and the `as_value` kwarg,
entirely.

**Unchanged:** the reactive hot path (`getindex`/`recompute!`/`invalidate!`/`peek`); the
autowrap codegen in `CellStruct.jl`; `CellVector._wrap_cell`; the comprehension seams;
`copy_cell_as` and `DocumentCopy` — all of these become trap-free with **zero edits**, because
they all end in `Cell(x)`, and the `copy_cell_as` function→thunk copy bug heals by the
constructor change alone.

**Reserved:** a `Computed` object itself can never be stored as a cell value — it is kernel
vocabulary, same class of reservation as the cell-kind names in `@document` field types (and
exactly the Lisp original's reservation of `computed-state`).

**Deferred non-goal:** an `@computed expr` sugar macro (the `(as …)` analogue, ≡
`Cell(Computed(() -> expr))`). It can layer on later without another migration; the sweep is
simpler as a pure spelling substitution.

## Runtime cost analysis

1. **Read/invalidate hot path: zero delta.** `getindex`, `recompute!`, `_invalidate_walk!`,
   `peek`, and the dependency-edge bookkeeping are not edited. Every path the performance
   counters track (`:reads`, `:computes`, `:invalidations`, `:writes`) executes the same code.
2. **Value construction: identical.** Non-function values take the same single inner-ctor path
   as today. Deleting the kwarg-bearing `::Function` method *removes* a method and its kwsorter
   from the constructor's table; dispatch for `Cell(x)` is otherwise unchanged.
3. **Computed construction: ≈ 0, bounded by one transient 16 B alloc.** The marker is one
   immutable struct with a single pointer field, consumed immediately by the inner constructor.
   When `ComputedCell(f)` / `Cell(Computed(f))` inlines, SROA eliminates the wrapper outright;
   the worst case is one short-lived 16-byte allocation. For scale: computed-cell construction
   already heap-allocates the closure *and* the mutable `ReactiveCell` (5 words + header ≈ 48 B
   after the lazy-edges optimization), so the delta is noise.
4. **Specialization / compile time: parity by design.** `Computed` is non-parametric on
   purpose. A parametric `Computed{F<:Function}` would force one method instance of the
   constructor per closure type across the ~408 swept sites, whereas today's `f::Function`
   argument is stored-not-called and thus (per Julia's specialization heuristics) typically not
   specialized per closure. Non-parametric keeps today's method-instance counts. The abstract
   `thunk::Function` field costs nothing downstream: it lands in the cell's already-abstract
   `thunk::Union{Nothing, Function}` field.
5. **New methods are dispatch-table entries only.** The guards and the `setindex!` bridge add
   candidates; concrete-typed write sites resolve statically, and fully-dynamic write sites see
   one extra candidate on the *cold* side of a pull-based system (writes are rare relative to
   reads by design).
6. **`copy_document` gets cheaper as well as correct** for function-valued cells: a plain value
   copy instead of constructing an invalid computed cell that recomputes (i.e. *calls the
   callback*) on next read.
7. **Verification (Phase 6): measured, and the marker is free.** `@allocated` per constructed
   cell, with the cells pushed into a sink so nothing is elided for not escaping (measuring
   without that reports 0 B for every path and proves nothing):

   | construction | bytes/cell |
   |---|---|
   | `Cell(1)` | 48 |
   | `Cell(f)` — function as a value | 48 |
   | `ComputedCell(f)` | 48 |
   | `Cell(nothing)` + `set_cell_function!` (marker-free equivalent) | 48 |

   The `Computed` wrapper costs **0 bytes**, better than the predicted ≤16 B worst case: it is
   consumed by the inner constructor and never escapes, so SROA removes it entirely. All four
   paths allocate exactly the `ReactiveCell` itself.

   Full-suite test-count parity also held at every phase (no field-count drift).

## Seal permissions

**Granted by the user on 2026-08-03 (in the conversation that produced this plan):** the
following sealed files may be modified for this plan. Upon first modification, flip each
`🔒` → `⬜` in `CLAUDE.md` and **leave them unsealed for later review** — they are re-sealed
only after that future review, not as part of this plan.

- `cell/ReactiveCell.jl` — constructor rework, `ComputedCell`, `setindex!` bridge, docstrings
- `cell/CellModule.jl` — include `CellComputed.jl`, export `Computed`, `ComputedCell`
- `cell/CellDefaults.jl` — the `ImmutableCell`/`MutableCell` guards
- `iomap/IoMapDefaults.jl` — 1 swept callsite
- `iomap/IoMapReconcile.jl` — 2 swept callsites

The new `cell/CellComputed.jl` enters the `CLAUDE.md` inventory as `⬜` at its include
position (after `CellInterface.jl`). Files touched that were never sealed:
`projection/ProjectionApi.jl` (1 site), `projection/ProjectionTemplate.jl` (13 sites), plus
visual/domain/base packages and omnetpp-julia.

## Migration plan (each phase = one commit; spellings coexist until Phase 3, so every phase is green)

Implementation runs in a dedicated sibling worktree (`/home/projectured/workspace/<name>`,
fresh `Pkg.instantiate`); the omnetpp-julia sweep is a separate commit in that repo (its
`[sources]` link straight to `projectured-julia/package`, so Phase 1 must be on
projectured-julia main — or reachable from the worktree omnetpp resolves — before Phase 2
lands there).

### Phase 1 — additive marker (projectured-julia) [x] **done**

- [x] `cell/CellComputed.jl`: the `Computed` struct + docstring + `show`.
- [x] `ReactiveCell.jl`: inner ctor `ReactiveCell{T}(c::Computed)` (the `new{T}()` +
      `thunk`/`valid=false` path, copied off the `::Function` method);
      `ComputedCell(f) = ReactiveCell{Any}(Computed(f))`;
      `Base.setindex!(c::ReactiveCell, ::Computed)` delegating to `set_cell_function!`.
- [x] `CellDefaults.jl`: guards `ImmutableCell(::Computed)`, `ImmutableCell{T}(::Computed)`,
      `MutableCell(::Computed)`, `MutableCell{T}(::Computed)` → clear errors.
- [x] `CellModule.jl`: include + exports (`Computed`, `ComputedCell`) + docstring.
- [x] `CLAUDE.md`: seal-list flips per the permissions section + the new `⬜` entry.
- [x] **Keep** the `::Function` thunk ctor and `as_value` for now (both spellings coexist).
- [x] Test: `test_cell()` 57/57; direct load check of all six new behaviours.

Decisions made during implementation:

- **No outer `ReactiveCell(::Computed)` is needed.** `ReactiveCell(value) =
  ReactiveCell{Any}(value)` already forwards a `Computed` into the new inner constructor,
  and `Cell` *is* `ReactiveCell{Any}`, so `Cell(Computed(f))` hits it directly. One method
  fewer than the plan assumed.
- **No typed `ComputedCell` convenience.** A repo-wide grep found exactly one typed thunk
  site (`package/kernel/test/cell/CellTest.jl:129`), so the typed spelling stays the honest
  `ReactiveCell{T}(Computed(f))` rather than earning sugar.
- **The guards live in `CellDefaults.jl`**, the only cell file with all three kinds in scope
  (`CellComputed.jl` is included before them). Its header now states that as its remit.
- `Computed` and `ComputedCell` collide with no existing name in any of the three repos.

### Phase 2 — spelling sweep [x] **done**

- [x] projectured-julia: 388 literal sites (`Cell(() -> …)`, `Cell(function … end)`; zero
      do-block forms exist) plus the one variable-thunk site
      `visual/main/widget/WidgetToGraphics.jl:730` (`Cell(build_fn)`) → `ComputedCell(...)`.
- [x] omnetpp-julia: 20 literal sites (presentation widgets). inet-julia: zero sites.
- [x] The one typed site, `package/kernel/test/cell/CellTest.jl:129` →
      `ReactiveCell{Int}(Computed(…))`.
- [x] `iomap/IoMapDefaults.jl`: two prose mentions (one wrapped across lines, so the sed
      missed it).
- [x] **Import fallout — the real work of this phase.** `ComputedCell` had to be added to
      every explicit `using/import …CellModule: …Cell…` symbol list: **142 files** in two
      passes. The first pass (58 files) only touched files that themselves say
      `ComputedCell`, which missed the case that actually bites — a **module aggregator**
      importing `Cell` by list while a *fragment* file of that module is the one using
      `ComputedCell` (`OmnetppPresentation.jl` vs `OmnetppWorkbenchToWidget.jl`). The second
      pass (84 files) therefore adds `ComputedCell` to *every* such list unconditionally,
      whether or not that file uses it. Unused imports are harmless; a missing one is a
      runtime `UndefVarError` on a path tests may not reach.
- [x] The umbrella `Projectured` needs no edit: it re-exports mechanically via `names()`.

Verification: omnetpp-julia **5164 pass / 0 fail / 0 error** (the 6 errors the first import
pass left are fixed). Sweep is semantics-preserving, so suite counts are expected to match
the pre-change baseline.

Method note: the sweep was two `sed` expressions, not a subagent — the codebase had exactly
two textual forms (`Cell(() ->`, `Cell(function`), no `do`-block or multi-line or qualified
(`X.Cell(`) variants, and no occurrences inside string literals. `\bCell\(` cannot match
inside `MutableCell(`/`ImmutableCell(`/`ComputedCell(`, so the substitution is safe and
idempotent.

### Phase 3 — tripwire flip [ ]

- [x] `ReactiveCell{T}(::Function)` now errors; `as_value` and the outer
      `ReactiveCell(f::Function; as_value)` are deleted.
- [x] `as_value`'s one real user (`ObjectToSyntax.jl`) moves to the interim
      `c = Cell(nothing); set_cell_value!(c, filter)` idiom — the same dance Widget.jl already
      does — because during this phase storing a function as a value has no constructor
      spelling. Phase 5 collapses all seven of these together.
- [x] **The tripwire immediately earned its keep: it found a whole class the grep could not
      see.** A bare lambda passed as a *positional argument to a `@document` constructor*
      relies on the autowrap (`$a isa Cell ? $a : Cell($a)`) turning it into a thunk — there
      is no `Cell(` token at the call site at all. `ProjecturedVisualExample` failed to
      precompile, which cascaded into the visual, domain **and** omnetpp suites (all three
      depend on it), so three of five suites never started.
- [x] Static audit for the whole class, since the tripwire only fires on executed code: for
      every `() ->` in both repos, resolve its enclosing call by scanning backwards across
      line breaks to the innermost unclosed `(` (a line-based grep misses multi-line calls —
      the very site that broke was one). 357 lambdas are not in a known thunk API; of those,
      only ones whose enclosing call is a **type constructor** can reach the autowrap.
      Classification of those:
    - **Safe — plain `struct`, so a `Function` is just a field value**: `SimulationModel`,
      `EditorDomain`, `Resource`, `MCPResource`, `Example`, `HoverProbeProjection`.
    - **Safe — `@document` with an explicit `::Function` constructor** that never reaches the
      autowrap: `TextString` (93 sites), `SyntaxLeaf`, `TextBlock`, `SyntaxConcatenation`;
      and `SyntaxNode`, whose keyword form routes through `_children(f::Function)` →
      `CellVector(f)`.
    - **Broken — `@document`, no `::Function` constructor → autowrap → thunk. 13 sites
      fixed**: `GraphicsLine` ×6, `GraphicsCircle` ×3, `GraphicsPolyline` ×2 (all in
      `visual/example/document/RotatingVector.jl` plus omnetpp's `Mm1kLive.jl`),
      `JsonNumber` ×1 (`domain/test/document/JsonTest.jl`), `SyntaxNavigation` ×1
      (`domain/main/sql/SqlToSyntax.jl`).
- [x] Re-audit reports 0 remaining, and all 12 packages using `ComputedCell` can resolve it.
- [x] **A third class, found by the next tripwire run: the internal forwarders.** A
      constructor whose *own* `::Function` method makes it "safe" from the autowrap still had
      to build the thunk somehow, and did it with `Cell(<variable>)` — invisible to any grep
      for `Cell(() ->`. One line, `text/Text.jl:167`
      (`TextString(content::Function, …) = TextString(Cell(content), …)`), accounted for
      **692 failures in the domain suite and 115 in visual**, because `SyntaxLeaf(f)`,
      `PrimitiveToText`, `PrimitiveToSyntax` and every `@projection_template` funnel through
      it. Fixed sites:
    - `visual/main/text/Text.jl:167` — the root.
    - `visual/main/syntax/Syntax.jl:352` — `SyntaxConcatenation(thunk::Function)`.
    - `domain/main/conversation/ConversationEditor.jl:465` and omnetpp
      `presentation/…/VectorPlot.jl:257` — `Cell(name)` where `name` is a locally-defined
      zero-arg function, so not even `::Function`-annotated.
- [x] Full baseline-diff suites in **both** repos: **all five match baseline exactly with the
      tripwire armed and zero hits** — kernel 480/3/2/485 (known Rule C), base 342,
      visual 49236 + 1 broken, domain 111161 + 5 broken, omnetpp 5164.

**Correction to a comment the fix touched.** `Syntax.jl`'s `SyntaxConcatenation(thunk::Function)`
carried the claim that a bare `Function` is "stored AS IT IS … the engine recognises one by
finding an unevaluated `Function` in the field". That is not what the code did: the `@document`
autowrap built `Cell(thunk)`, a *computed* cell, so `_find_conditional`'s
`getfield(out, f)[]` evaluates the thunk and gets the children vector, never a `Function`.
The migration preserves the real behaviour (`ComputedCell(thunk)`) rather than the comment's
description, and the comment now states what the code does. Worth noting: after this plan a
field genuinely *can* hold a function unevaluated, so the mechanism the comment describes
becomes implementable for the first time — but changing `_find_conditional` is a behaviour
change and is not part of this plan.

**Three classes, not one.** The sweep had to cover: (1) the explicit `Cell(() -> …)` spelling
— greppable, 408 sites; (2) a bare lambda passed to a `@document` constructor, caught by the
autowrap — needs a cross-line enclosing-call audit, 13 sites; (3) a forwarder building the
thunk from a *variable*, `Cell(f)` — findable only by knowing `f` holds a function, 4 sites.
The original survey counted class (1) exactly, guessed class (3) at one site, and missed class
(2) entirely. Only the tripwire found (2) and (3); no amount of grepping would have.

**Lesson for the plan's own premise.** The survey's "generic wrap seams are healed with zero
edits" claim was right about the *seams* but hid this: the seams are healed, yet the call sites
that were *feeding a function into* those seams still meant "thunk". The sweep had to cover
both the explicit `Cell(f)` spelling and the implicit constructor-argument one, and only the
second needed a real audit. A grep for `Cell(` can never find the second.

### Phase 4 — remove tripwire [x] **done**

- [x] Deleted the error method. `Function` now flows into the generic value path: `Cell(f)`
      stores `f`, verified together with `copy_cell_as` keeping it a value (the bug is dead as
      of this commit) and `ReactiveCell{Function}(f)`.

### Phase 5 — simplify workarounds + regression tests [x] **done**

- [x] `visual/main/widget/Widget.jl` — all six `Cell(nothing); set_cell_value!(…)` dances
      (`validator` ×2, `action` ×2, `gestures`, `callback`) are now plain `Cell(x)` field
      values; their trap-explaining comments came out with them.
- [x] `visual/main/syntax/ObjectToSyntax.jl` — the `filter` predicate is passed straight
      through (`filter = filter`); the `as_value` ternary and the now-unused `set_cell_value!`
      import are gone.
- [x] omnetpp-julia `simulator/main/src/lifecycle/Optimization.jl` — dropped the
      `ImmutableCell` double-box and the paragraph explaining it.
- [x] omnetpp-julia `simulator/main/src/engine/SequentialSimulator.jl` — the
      `@document ImmutableCell` header no longer justifies itself by the thunk trap (the kind
      is still right: a heap entry never changes, and the wrapper is zero-cost).
- [x] omnetpp-julia `presentation/main/src/project/OmnetppProject.jl` — removed the stale
      comment describing `as_value` protection the code never had.
- [x] Regression tests: kernel `CellTest.jl` gains a "a function is a value" testset
      (`Cell(f)` stores/`ComputedCell(f)` computes, both write forms, both guards, and
      `copy_cell_as` keeping a function a value) — 57 → 71 assertions;
      `DocumentContractTest.jl` gains "copy_document preserves a function-valued field" for
      both the same-kind and kind-converting copies.

**A second latent bug this fixes, found while simplifying.** omnetpp's *callable objective*
(`SimulationOptimization(cfg; objective = r -> …)`) was **broken**, not merely clumsy. The
`ImmutableCell` box only helps if the macro passes it through, but the reactive autowrap is
`$a isa Cell ? $a : Cell($a)` and an `ImmutableCell` is not a `Cell` — so it was wrapped again
and `o.objective` read back as the `ImmutableCell` wrapper, which is not callable;
`score_simulation`'s `objective(result)` would have thrown. No test covered it (every existing
test uses a `Symbol` objective). Removing the box fixes it, and
`package/simulator/test/runtests.jl` now covers the callable path (5164 → 5166).

### Phase 6 — docs + verification [x] **done**

- [x] `documentation/architecture-requirements.md` — **AR-NO-NESTED-CELL rewritten**. It used
      to state the trap *as the rule*; the ban now covers `Cell` and `Computed` (both are cell
      vocabulary the constructor consumes), and it says explicitly that a `Function` is an
      ordinary field value.
- [x] Same file: `Cell(() -> …)` → `ComputedCell(() -> …)` in AR-PURE-THUNK,
      AR-DERIVED-CELLS, AR-SHARED-CHILDREN-IOMAP, AR-REACTIVE-OUTPUT-SELECTION; and
      AR-USE-PROJECTION-MACRO no longer gives "a `Function` field" as a reason the macro
      can't be used.
- [x] `package/kernel/doc/cell.md` — construction section rewritten around the marker;
      `macros.md` — the "Gotchas" bullet and the plain-struct-projection rationale;
      spelling swept through `projection-system.md`, `selection.md`,
      `documentation/projectured-overview.md`, `documentation/tutorial-new-domain.md`.
- [x] `as_value` no longer appears anywhere in the repo outside this plan's own history.
- [x] Micro-benchmarks run; results recorded in the runtime cost analysis above (the marker
      costs 0 bytes).
- [x] Seal markers: `cell/CellModule.jl`, `cell/CellComputed.jl` (new), `cell/ReactiveCell.jl`,
      `cell/CellDefaults.jl`, `iomap/IoMapDefaults.jl`, `iomap/IoMapReconcile.jl` are `⬜`,
      **left unsealed for review** as agreed. No other sealed file was modified (checked by
      diffing the full change set against the `🔒` list).
- [x] Move this plan to `plan/done/`.

## Final state

All five suites at baseline, in both repos:

| suite | result | vs. baseline |
|---|---|---|
| kernel | 496 pass / 3 fail / 2 error | +16 pass (new regression tests); fails are the pre-existing Rule C set |
| base | 342 pass | unchanged |
| visual | 49236 pass / 1 broken | unchanged |
| domain | 111161 pass / 5 broken | unchanged |
| omnetpp-julia | 5166 pass | +2 (new callable-objective test) |
| inet-julia | 2297 pass | unchanged (no cell-thunk usage; load-checked) |

Two latent bugs fixed on the way: `copy_cell_as` turning a function-valued cell into a thunk
on every document copy, and omnetpp's callable `SimulationOptimization` objective, which could
never have been called.

Unrelated pre-existing failure, confirmed not caused by this work:
`ProjecturedAdaptagramsExample` does not precompile because ODBC cannot load the PostgreSQL
driver (a bare `ODBC.Connection` fails identically with no ProjecturEd code in the stack; that
package last built on 2026-07-13).

## Follow-up found during implementation — `CellVector(f::Function)` (NOT in this plan)

`base/main/collection/CellVector.jl:45` has the *same* defect in a second place:

```julia
CellVector(items...)      = CellVector(Cell[Cell(x) for x in items])   # 1 arg → 1 ELEMENT
CellVector(f::Function)   = …set_cell_function!(…)                     # 1 arg → COMPUTED elements
```

so `CellVector(callback)` cannot mean "a one-element vector holding a callback" — computedness
is again inferred from the argument's runtime type. Its forwarders inherit it:
`make_children_container(thunk::Function)`, `Syntax._children(f::Function)`,
`TextBlock(f::Function)`, `TextLine(f::Function)`, `SyntaxNode(…, f, …)`. Roughly **92**
`CellVector(() -> …)` call sites plus ~7 forwarders.

**Deliberately left alone.** It is a separate ambiguous constructor in another package, this
plan's goal holds without it (`CellVector([f])` already stores `f` as a value, because the
element path goes through `Cell(x)`, which this plan fixes), and after Phase 4 nothing
regresses — `CellVector`'s behaviour is simply unchanged. Sweeping it is a scope decision for
the user, not a consequence of this one.

The fix, if wanted, is the same shape: `CellVector(::Computed)` replaces
`CellVector(f::Function)`, the forwarders pass `Computed(f)` down while keeping their own
unambiguous `::Function` signatures, and `CellVector(f)` then falls through to the variadic
as a one-element vector.

Not a defect, by contrast, and correctly out of scope: constructors like
`TextString(content::Function, …)`, `SyntaxLeaf(f::Function)`, `WidgetLabel`'s
`set_cell_function!` methods. There the field's value type (a `String`, a syntax node) admits
no callable, so a `Function` argument has exactly one possible meaning. Ambiguity — not the
`::Function` dispatch itself — is what makes a trap.

## Survey data (2026-08-03, for sizing)

| what | projectured-julia | omnetpp-julia | inet-julia |
|---|---|---|---|
| literal thunk ctor sites (`Cell(() ->`, `Cell(function`) | 388 | 20 | 0 |
| variable-thunk ctor sites | 1 (WidgetToGraphics.jl:730) | 0 | 0 |
| real `as_value` uses | 1 (ObjectToSyntax.jl:290) | 0 (1 stale comment) | 0 |
| `set_cell_function!` callsites (unchanged by this plan) | 131 | 62 | 0 |
| function-as-value workaround sites | 7 (Widget.jl ×6, ObjectToSyntax) | 1 (Optimization.jl) | 0 |

Generic wrap seams (all healed by the constructor change alone, zero edits): the
`@cell_struct`/`@document` autowrap ctor (~401 document structs), `CellVector._wrap_cell`,
~72 `Cell[Cell(x) …]` comprehensions, `Operations.jl` insert! replay, `copy_cell_as` +
`DocumentCopy`.

Kernel files containing swept sites: `iomap/IoMapDefaults.jl` (1), `iomap/IoMapReconcile.jl`
(2), `projection/ProjectionApi.jl` (1), `projection/ProjectionTemplate.jl` (13).

Lisp precedent: `(as body)` → `make-computed-state` in
`projectured-lisp/source/util/computed.lisp:332-347`; slot machinery dispatches on
`computed-state-p` only — computedness is syntactic, never inferred from `functionp`.
