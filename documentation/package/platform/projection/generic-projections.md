# Generic Projections

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../../design/system-anatomy.md)

Generic projections are **input-domain-independent**: they operate on any
document *by structure, not by type*, copying, sorting, reversing, filtering,
focusing, preserving, or reflecting over it without dispatching on any specific
domain. That input-independence is the defining property of the nine projections
below; each is a single struct subtyping `Projection`. Eight of them live in
`source/platform/projection/generic/`; the ninth, `ObjectToWidget`, lives in
`source/platform/widget/ObjectToWidget.jl`. *Most* also preserve the domain (same
domain in and out). The
reflection-driven `ObjectToWidget` is the one that does not preserve the
domain. It reflects over any object, so it stays fully input-independent, but
it produces a widget form. It belongs here by the input-independence test, even
though it changes the output domain.

| Projection | Effect on the output |
|---|---|
| `IdentityProjection` | Identity — output is the same object as the input |
| `ConstantProjection` | Constant — always emits a fixed `output` |
| `CopyingProjection` | Deep recursive copy where every child is re-projected via the `recursion` argument |
| `ReversingProjection` | Reverses the elements of a collection |
| `SortingProjection` | Sorts a collection by a configurable `by`/`lt`/`rev` |
| `FocusingProjection` | Navigates into a sub-document via a `Reference` |
| `FilteringProjection` | Restricts a collection to the elements matching a predicate |
| `SearchingProjection` | Walks the input and collects every object with a field matching a `Regex`, as a flat `CellVector` |
| `ObjectToWidget` | Reflection-driven form: emits a labelled control row per editable `Cell` field of the object |

## IdentityProjection

```julia
struct IdentityProjection <: Projection end
```

Pass-through. `print_document` returns `SimpleIoMap(p, input, input)` —
the *same* object on both sides. The reference maps are the identity.
`read_intent` answers a `KeyPress`, a `KeyDown`, a `MouseClick` and a
`CollectIntents` with `read_gesture` of its input document, as the default
leaf reader of the kernel does; it passes any `Operation` through unchanged;
and it answers `nothing` for any other payload, such as a `MouseMove`. So a
raw gesture that no layer below claims never comes back disguised as the
operation of the read. Useful as a no-op branch inside dispatchers (e.g.
"sort entries, preserve everything else").

## ConstantProjection

```julia
ConstantProjection(output)
```

Always emits the stored `output` regardless of input. The reader returns
`nothing` for every event. Useful for injecting constant content (e.g.
a placeholder when a sub-tree is collapsed).

## CopyingProjection

The workhorse of `ApplyAtProjection`. Recursively re-projects every child
of the input with `print_child(recursion, child, child_ctx)`, then
rebuilds an output struct/`CellVector`/`ListNode` of the same shape with
the new outputs in place. It is strictly domain-independent: it has no
`read_intent` method of its own, and has no reference to any specific domain.
The default reader re-targets selection and edit operations through
`map_reference_backward`. Key behaviours:

- For a `CellVector`, eagerly projects every slot.
- For a `ListNode`, projects only the head eagerly; `prev`/`next` are
  *lazy* — each direction is a `set_cell_computation!` computation that projects only when read.
  This is what makes copying an infinite linked list cheap.
- For a struct, projects every field whose value is a `Document` and
  passes non-document fields through unchanged.
- Reference mapping (`map_reference_forward` / `_backward`) delegates into
  the child iomap stored in `CopyingIoMap.children`, so a
  reference into the input is faithfully translated through the copied
  spine.

The CopyingProjection's IoMap also stores `recursion` and `base_ctx`
(the `PrinterContext`) so it can lazily project a ListNode child on demand
when a backward reference points there.

## ReversingProjection

```julia
print_document(::ReversingProjection, recursion, input, ctx)
```

Reverses the elements. The reference map flips an index `i` to
`n + 1 - i`. Combined with `ApplyAtProjection`, this lets you display a
collection in reverse order while keeping the underlying document and the
selection mechanism unchanged.

## SortingProjection

```julia
SortingProjection(; by = identity, lt = isless, rev = false)
```

Sorts a collection at print time. `SortingIoMap.index_map[j]`
holds the input index that ended up at output position `j`, which the
reference maps use for the round-trip:

- forward: input index `i` → output `j = findfirst(==(i), index_map)`
- backward: output index `j` → input `index_map[j]`

Per-element child iomaps are stored in `element_iomaps` so deeper
references translate correctly.

## FocusingProjection

```julia
FocusingProjection(; part_type = Any, part = EmptyReference())
```

Projects the sub-document reached by following `part` from the input root.
`part_type` constrains the legal target type. The reader handles three
gestures:

- A `ReplaceSelectionOperation` is translated by prepending `part` to the
  selection path.
- Ctrl-`,` produces a `ReplaceFocusPartOperation` that drops the last step
  of `part`, to zoom out one level.
- Ctrl-`.` produces a `ReplaceFocusPartOperation` that sets `part` to the
  longest prefix of the current selection whose target node matches
  `part_type`, to zoom in to the deepest legal focus along the cursor.

The operation itself reassigns `projection.part` and
`projection.part_evaluator`, so the projection is reactive. Subsequent
prints navigate to the new sub-document automatically.

## Composing generic projections

Generic projections are designed to be wrapped by higher-order projections.
The canonical pattern is `ApplyAtProjection`:

```julia
# Sort the entries of every nested object in the document
ApplyAtProjection(@reference(entries), SortingProjection(by = e -> e.key))
```

`IdentityProjection` and `CopyingProjection` are also the building blocks
behind `ReferenceDispatchingProjection` cases: preserve everywhere except
at the target path, apply the real transformation there, and copy the
spine that leads to it.
