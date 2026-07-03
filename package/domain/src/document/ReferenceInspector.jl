"""
    ReferenceInspectorDocumentModule

`ReferenceInspector` — a small display Document that holds a single
`reference` (a `ReferencePath`, or `nothing`) together with the `target`
document the reference points into. It is projected by
`ReferenceInspectorToText` into a two-section `TextText`: the compact,
Julia-printed shape on top and the reverse-order human-readable narrative
below.

It exists so the "what reference is this?" panel is a first-class,
dispatchable, testable component rather than an example-local thunk. The
hover click-reference inspector ships one of these as the `content` of its
follower window (see `HoverProbeProjection`), but anything that wants to show
a reference both ways (a status bar, a debugger pane) can reuse it.

`target` is needed only by the human-readable form, which names the Julia
type of the value each step is applied to via `evaluate_reference`.
"""
module ReferenceInspectorDocumentModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference

export ReferenceInspector

"""
    ReferenceInspector(; reference, target)

A display document pairing a `reference` (`ReferencePath` or `nothing`) with
the `target` document it points into.

# Fields

- `reference::Reference` — the reference to display. `nothing` renders as a
  single "no target" line.
- `target::Any` — the document `reference` is rooted at; used by the
  human-readable projection to resolve the parent type of each step. May be
  `nothing` when no type narration is wanted.
"""
@document struct ReferenceInspector
    reference::Reference
    target::Any
    selection::Reference
end

ReferenceInspector(; reference = nothing, target = nothing) =
    ReferenceInspector(Cell(reference), Cell(target), Cell(nothing))

end # module
