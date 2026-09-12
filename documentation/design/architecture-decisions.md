# Design Decisions

> **Kind:** decision · **Status:** current · **Stands on:** [accepted-requirements.md](../requirement/accepted-requirements.md), [system-anatomy.md](system-anatomy.md)

This document explains the *why* behind ProjecturEd's key architectural
choices. For the *what* (module inventory, package/layer/slice structure) see the
[architecture guide](system-anatomy.md). For the full reference/selection mechanism
see the [selection deep dive](../package/kernel/selection.md).

---

## 1. Pull-based reactivity (not push-based)

The `Cell` system is **pull-based / lazy**: invalidation propagates eagerly
(marking cells stale), but recomputation happens only on read. This matches
ProjecturEd's performance strategy:

- **Laziness** — only the visible portion of a document is ever computed. A
  JSON array with 10 000 elements projects only as many rows as fit on screen.
- **The reader is event-driven** — only the projection path touched by the
  current event is traversed; off-screen projections are never invoked.

A push-based system (e.g. Observables) would eagerly recompute every
downstream dependency when any cell changes, wasting work on content that is
not visible and not relevant to the current event. Pull-based evaluation gives
the incremental recomputation for free: if a cell's value hasn't been read
since its last invalidation, no work is done.

## 2. Structural vs. value incrementality

Every domain module distinguishes two kinds of changes:

- **Value changes** — e.g. changing a JSON string's content. Invalidates only
  the leaf cell in the syntax tree and the corresponding text span. The span
  list itself stays cached; the word-wrap layout is unchanged.
- **Structural changes** — e.g. adding a JSON array element. Invalidates the
  children cell of the affected array, triggering a rebuild of that subtree's
  flat representation.

This two-level strategy avoids full-document recomputation for the common case
(editing a single field value).

## 3. Every field is a `Cell`

All domain types wrap every field in a `Cell`, even fields that rarely change
(like static delimiters). This uniform approach:

- Keeps the type hierarchy simple — no separate "static" vs "reactive" variants.
- Allows any field to become computed later without changing the type definition.
- Enables projections to be expressed as simple thunks that read upstream cells.
- Makes the `@document` macro straightforward: it just intercepts
  `getproperty` / `setproperty!` to unwrap/wrap the `Cell` transparently.

The cost is a small amount of heap allocation per field. In practice this is
dominated by the rendering work and is not a bottleneck.

## 4. Multiple dispatch for projections

Julia's multiple dispatch is a natural fit for ProjecturEd's
**type-dispatch projection** pattern. `print_document` dispatches on the
concrete projection struct *and* the input document type — no visitor pattern,
no explicit type-case, no abstract method table.

```julia
function print_document(p::JsonStringToSyntaxLeaf, rec, s::JsonString, ctx)
    ...
end

function print_document(p::JsonArrayToSyntaxNode, rec, a::JsonArray, ctx)
    ...
end
```

`TypeDispatchingProjection` wraps a map of `Type → Projection` and uses Julia's
`typeof` to select the right sub-projection at runtime. For the common recursive
case `RecursiveProjection` passes itself as the `recursion` argument, so the
inner projection can recurse without knowing about the outer wrapper.

## 5. Module-per-domain / module-per-projection

Each domain and each projection lives in its own `module`. This mirrors
ProjecturEd's principle that domains are independent of each other and of
projections. Dependencies are explicit: `JsonToSyntax` imports from `Json` and
`Syntax` but knows nothing about `Text` or `Graphics`.

The trade-off is verbosity in `Projectured.jl` (the root module that assembles
them all), but it prevents accidental coupling and makes the dependency graph
auditable.

## 6. `print_document` returns an IO map

Rather than returning just the output document, every `print_document` method
returns an `IoMap` that carries both the input and the output (and any
additional mapping data the reader needs). This ensures the reader always has
access to both contexts without any additional bookkeeping.

`ChainingProjection` collects all step IO maps into
`ChainingIoMap.step_iomaps`, enabling the reader to walk backward
through each step:

```julia
function read_intent(seq, recursion, change::Intent, iomap)
    change = read_intent(seq.projections[end], recursion, change, iomap.step_iomaps[end])
    for i in (n-1):-1:1
        change.operation === nothing && return change
        change = read_intent(seq.projections[i], recursion, change, iomap.step_iomaps[i])
    end
    return change
end
```

## 7. Shared selection cell

For a simple leaf pipeline (e.g. `JsonString → SyntaxLeaf → Text`), the
printer passes the *same* `selection::Cell` object from the `JsonString` struct
through to the `SyntaxLeaf` and on to the `Text`. All three objects reference
the same `Cell` instance.

When `evaluate_operation` writes `doc.selection[] = new_path`, the change is
immediately visible at every projection level without any wiring, because the
`Text.selection` computed cell reads `leaf.selection` which reads
`json_string.selection` — they are the same cell. The cursor redraws
automatically.

This optimisation is valid for *leaf-to-leaf* projections where the input and
output selection formats are identical. For compound projections (arrays,
objects) each child document manages its own `selection` cell and
`set_selection!` sets them individually. See
[Selection projection under recursion](../package/kernel/selection.md#selection-projection-under-recursion).

## 8. `ProjectionReferenceStep` for projection-introduced elements

When the cursor moves onto a character introduced by a projection (e.g. the
`"` delimiters of a JSON string), there is no corresponding index in the JSON
document to point to. Rather than clamping or skipping these positions, the
reference path contains a `ProjectionReferenceStep` step:

```julia
struct ProjectionReferenceStep <: ReferenceStep
    projection::Any             # which projection introduced this element
    output_path::Reference  # where within that projection's output
end
```

This allows the editor to represent a cursor on the opening `"` as:
```
ProjectionReferenceStep(json_string_proj, FieldReferenceStep("open") + PositionReferenceStep(0))
```

The reader knows how to translate this back: a `ProjectionReferenceStep` to the
`open` field means the cursor is on the delimiter, not in the value, so no
JSON-domain path can represent it — the `ProjectionReferenceStep` is kept as-is
and stored in the `JsonString.selection`.

## 9. `KeyPress` abstraction

SDL keysyms are converted to a `KeyDown(key::Symbol, modifiers::ModifierKeys)`
struct in the backend before being passed to `read_intent`. This decouples
projections from the SDL backend — a future terminal or web backend produces
the same events, and projection reader code stays unchanged.

## 10. Propagation is write-driven, not value-driven

When a primitive cell is written, the engine invalidates its transitive
dependents **unconditionally** — there is no `old == new` short-circuit, and a
computed cell that recomputes to an unchanged value does not stop propagation.
The engine is deliberately *not* glitch-free or value-stabilising.

The reason is simplicity and predictability: change detection by value would
require every cell to retain and compare its previous value (and to define a
meaningful `==` for arbitrary document payloads), and it interacts badly with
laziness — a cell that was never pulled has no "previous value" to compare
against. Keeping propagation keyed on *writes* makes the cost model trivial to
reason about: work is proportional to what is written and then pulled, full
stop. The practical consequence to keep in mind is that writing a cell its own
current value is **not** free — e.g. a printer that rewrites `selection` every
frame pays to recompute the whole subtree that reads it. See
[the reactive invariants](../package/kernel/cell.md#invariants-the-engine-relies-on).

---

## Key differences from the original ProjecturEd (Common Lisp)

| Aspect | Original (Lisp) | Julia reimplementation |
|---|---|---|
| Language | Common Lisp, CLOS | Julia, multiple dispatch |
| Reactivity | `computed-class` MOP slots | Explicit `Cell` with manual thunks |
| Struct magic | Computed slots via metaclass | `@document` macro + `Cell` wrapping |
| Projections | CLOS generic functions | Lightweight structs + `print_document` dispatch |
| Selection cells | Shared by reference | Shared by reference (same approach) |
| `ProjectionReferenceStep` | Different mechanism | `ProjectionReferenceStep` step in path |
| Scope | Dozens of domains | Complete end-to-end path + expanding |
