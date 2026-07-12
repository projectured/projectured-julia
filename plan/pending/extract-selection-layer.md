# Extract a selection layer (kernel layer 4)

Pull the **selection primitives** out of the reference layer (`reference/Selection.jl`)
and the operation layer (`operation/Operations.jl`) into their own kernel layer,
`selection/`, inserted between reference (L3) and operation (L5).

## Why here (not above operation)

Selection primitives depend only on Document (L2) + Reference (L3). The operation
layer *uses* them: `SelectNextInsertionOperation.evaluate` calls `set_selection!`,
`ReplaceSelectionOperation.evaluate` calls `update_selection!`, and `replace_document`
builds a `ReplaceSelectionOperation`. `ReplaceSelectionOperation` is a peer of
`ReplaceReferencedValueOperation` (co-located reroot methods, bundled in a
`CompoundOperation`), so it **stays in the operation layer** — exactly as a value
operation stays with operations while the reference primitives it calls live below.
Selection primitives are to `ReplaceSelectionOperation` what reference primitives are
to `ReplaceReferencedValueOperation`.

## New layer numbering

reference stays 3; **selection = 4**; operation→5, device→6, backend→7, projection→8,
agent→9, editor→10 (10 layers total).

## What moves into `selection/Selection.jl`

- From `reference/Selection.jl` (then delete it): `get_selection(::Document)`.
- From `operation/Operations.jl` (lines ~466–653): `clear_selection!`, `set_selection!`,
  `with_selection`, `_set_selection_walk!`, `replace_selection!`, `update_selection!`,
  `_sync_selection!`, `_selection_child`, `_mutate_terminal_step!`.

Stays in operation: `ReplaceSelectionOperation`, `SelectNextInsertionOperation`
(+ `_selection_owner_node`/`_preorder_documents!`), `replace_document`, the reroot
methods — they call down into the selection layer.

## SelectionModule imports

- `..CellModule: AbstractCell`
- `..DocumentModule: Document`
- `..ReferenceModule: ConcreteReferencePath, ReferencePath, FieldReference, RangeReference,
  annotate_reference_types, strip_reference_types, is_reference_equal`

Exports: `get_selection, clear_selection!, set_selection!, with_selection,
replace_selection!, update_selection!`.

## Wiring / steps

1. New files: `selection/SelectionLayer.jl`, `selection/SelectionModule.jl`, `selection/Selection.jl`.
2. `ProjecturedKernel.jl`: `include("selection/SelectionLayer.jl")` after reference; "nine…"→"ten", renumber comments.
3. `ReferenceModule.jl`: drop `include("Selection.jl")` + the 4 selection exports; delete `reference/Selection.jl`.
4. `OperationModule.jl`: import selection fns it calls (`set_selection!`, `update_selection!`, `clear_selection!`) from `..SelectionModule`; stop exporting the moved primitives; drop the reference-imported selection generics.
5. `Operations.jl`: delete the moved block (466–653).
6. Consumers: add `const SelectionApiModule = ProjecturedKernel.SelectionModule` in `ProjecturedVisual`/`ProjecturedDomain`; `const SelectionModule = ProjecturedKernel.SelectionModule` in `ProjecturedBase`. Repoint imports in `base/Primitive.jl`, `domain/VersioningToAny.jl`, `visual/ClipboardToAny.jl`, `domain/{Json,Yaml,Xml}.jl`, `domain/InsertionToSyntax.jl`.
7. Layering guard: insert `"selection"` in the kernel `layers` list (`ProjecturedKernelTest.jl:92`).
8. `CLAUDE.md` seal list: insert Layer 4 selection (⬜), renumber 5–10.
9. Docs: architecture.md, concepts.md, reference.md, selection.md, orientation.md, AR-doc — new layer + renumber.

## Verify

`test_kernel_layering()` + `test_kernel()`; then base/visual/domain suites.

## Commits

1. Code move + wiring + guard (green kernel/base/visual/domain).
2. CLAUDE.md seal list + docs renumbering.
