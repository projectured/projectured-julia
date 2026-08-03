# Eliminate the CellVector thunk trap

**Status: done.** Implemented 2026-08-03 on `main` in projectured-julia and
omnetpp-julia. Follow-up to [cell-computed-marker.md](../done/cell-computed-marker.md),
which fixed the same defect in the `Cell` constructor. Approved 2026-08-03.

## Problem

`CellVector` decides what a single argument *means* from its runtime type:

```julia
CellVector(items...)      = CellVector(Cell[Cell(x) for x in items])   # 1 arg → 1 ELEMENT
CellVector(f::Function)   = …set_cell_function!(…)                     # 1 arg → COMPUTED elements
```

so a callable cannot be an element. It is not a near-miss — the failure is silent and
produces plausible garbage:

```julia
mycb() = "I am a callback"
CellVector(mycb)     # → a 15-element vector of Chars: 'I',' ','a','m',' ','a',' ','c',…
```

The thunk is called, returns a `String`, and `Cell[Cell(x) for x in f()]` iterates it into
characters. No error, no warning.

`CellVector` is a *generic* container (elements are `Any`), which is exactly what makes a
`Function` ambiguous there — the same property that made `Cell(f)` ambiguous.

**The predecessor plan made this worse by leaving it.** Three of the four ways to put a
function into a `CellVector` now store it as a value, because they all route through `Cell(x)`:

| spelling | today |
|---|---|
| `CellVector([f])` | holds `f` ✓ |
| `push!(cv, f)` | holds `f` ✓ |
| `CellVector(1, 2, f)` | holds `f` ✓ |
| `CellVector(f)` | **calls it** ✗ |

Before that plan everything called it — wrong, but at least uniform. This one is the odd case
out, which is worse than a consistent rule.

**Not in scope, and not defects.** `SyntaxNode(open, close, sep, f::Function)`,
`TextBlock(f::Function)`, `TextLine(f::Function)`, `Syntax._children(f::Function)`,
`make_children_container(thunk::Function)` keep their `::Function` signatures. Their elements
are syntax nodes and text spans, which can never be callables, so a `Function` argument there
has exactly one possible meaning. Ambiguity is what makes a trap — not `::Function` dispatch.
They change only in what they pass *down*.

## Design

Mirror the `Cell` fix exactly, reusing its vocabulary:

| spelling | result |
|---|---|
| `CellVector(x)` | a one-element vector holding `x` — for every `x`, callables included |
| `CellVector(Computed(f))` | elements derived from `f` |
| `ComputedCellVector(f)` | convenience ≡ `CellVector(Computed(f))` |

`ComputedCellVector` is named for guessability against its sibling `ComputedCell` (the
codebase now reads `ComputedCell(f)` for "a cell that computes"), and it keeps the call-site
sweep a pure textual substitution. Both spellings work, exactly as `Cell(Computed(f))` and
`ComputedCell(f)` both do.

**Deleted:** `CellVector(f::Function)`. A bare function then falls through to the variadic and
becomes one element, which is the whole point.

Exports: `ComputedCellVector` joins `CollectionModule`'s export list. `Computed` itself is
already exported from `CellModule` and re-exported by the umbrella.

## Runtime cost

Nil, and for the same reason as the predecessor: `Computed` is an immutable single-pointer
struct consumed immediately by the constructor, so SROA removes it (measured at **0 bytes** in
the `Cell` case). The elements cell is still built by `set_cell_function!` exactly as now —
this changes only how the constructor is *told* to build one. No hot path is touched.

## Survey (2026-08-03)

| what | projectured-julia | omnetpp-julia | inet-julia |
|---|---|---|---|
| `CellVector(() -> …)` call sites | 82 | 6 | 0 |
| forwarders passing a `Function` down | 6 | 0 | 0 |

The six forwarders: `collection/CellVector.jl:247` (`make_children_container`),
`syntax/Syntax.jl:450` (`_children`), `syntax/Syntax.jl:589` and `:602` (`SyntaxNode`),
`text/Text.jl:249` (`TextBlock`), `text/Text.jl:286` (`TextLine`), plus
`widget/WidgetToGraphics.jl:737` (`_reactive_canvas_auto`, an un-annotated `elems_fn`).

## Migration (each phase one commit; both spellings coexist until Phase 3)

Implemented on `main` in both repos, as the user directed for the predecessor plan.

### Phase 1 — additive marker support [x] **done**

- [x] `CellVector(c::Computed)` alongside the existing `CellVector(f::Function)`.
- [x] `ComputedCellVector(f) = CellVector(Computed(f))`, exported from `CollectionModule`.
- [x] Test: `test_base()` 342; a direct check that both spellings build a computed elements vector.

### Phases 2–3 — spelling sweep + tripwire [x] **done** (one commit)

Committed together: the sweep was verified *with* the guard armed, so separating them would
have meant a commit nobody ran the suites against.

- [x] **92** `CellVector(() -> …)` sites → `ComputedCellVector(…)` (86 in projectured-julia,
      6 in omnetpp-julia). Checked first for the variants that bit last time: no `do`-block,
      no qualified `X.CellVector(`, no in-string occurrences. The one multi-line
      `CellVector(` (`visual/example/document/Collection.jl:2`) is a variadic *element* list,
      not a thunk, and was correctly left alone.
- [x] **Eight** forwarders pass `Computed(f)` down, keeping their `::Function` signatures:
      `make_children_container`, `Syntax._children`, `SyntaxNode` ×2, `TextBlock`, `TextLine`,
      `WidgetToGraphics._reactive_canvas_auto`, plus a prose mention in `Syntax.jl`.
- [x] `ComputedCellVector` added to **89** files' `using …CollectionModule:` lists,
      unconditionally — the aggregator-vs-fragment gap that cost a verification round on the
      predecessor.
- [x] Static audit: 0 packages use `ComputedCellVector` without a provider.
- [x] `CellVector(::Function)` errors, naming `ComputedCellVector`.
- [x] Full suites in both repos **at baseline with the guard armed, zero hits**.

The two classes the predecessor's grep missed were audited for explicitly and both came back
empty: no `CellVector(<locally-defined function>)` anywhere, and every bare lambda reaching a
*type constructor* belongs to the already-classified safe set (`TextString`, `SyntaxNode`,
`SyntaxLeaf`, `TextBlock`, `SyntaxConcatenation` — all with explicit `::Function` methods —
or the plain structs `SimulationModel`, `EditorDomain`, `Resource`, `MCPResource`, `Example`,
`HoverProbeProjection`). Unlike the `Cell` migration, this sweep was clean on the first pass.

### Phase 4 — remove tripwire [x] **done**

- [x] Deleted the error method; `CellVector(f)` is a one-element vector holding `f`.
- [x] Regression test in `base/test/document/CollectionTest.jl` ("a function is an element"):
      the one-element case, agreement across `CellVector([f])` / the variadic / `push!`, and
      `ComputedCellVector(f)` deriving *and re-deriving* on upstream change. base 342 → 350.

      The test caught a real quirk while being written: `CellVector(1, f)` is **not** two
      elements — a bare 2-arg call resolves to the macro's `(elements, selection)` inner
      constructor, as the source comment documents. The assertion uses three arguments.

### Phase 5 — docs [x] **done**

- [x] `package/base/doc/collection.md` — construction table, the lazy-children example, and
      the "computed collection" note; states that a single argument is always one *element*.
- [x] `package/kernel/doc/cell.md` idiom list. `macros.md` and
      `architecture-requirements.md` needed no change — their `CellVector` mentions are about
      per-slot granularity, not the constructor.
- [x] Move this plan to `plan/done/`.

## Baselines to hold

kernel 496 pass / 3 fail / 2 error (pre-existing Rule C), base 342, visual 49236 + 1 broken,
domain 111161 + 5 broken, omnetpp-julia 5166, inet-julia 2297. Run memory-capped
(`systemd-run --user --scope -p MemoryMax=14G`), omnetpp with `-t 4`.
