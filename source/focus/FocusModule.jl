"""
    FocusModule

Focus traversal — the generic walk that finds the first / last focusable leaf
in a document subtree.

Focus is selection. These pure helpers locate the *first* / *last* focusable
leaf as a relative whole-element (∅) path, mirroring the generic field/element
descent the selection machinery uses, so the produced path matches the
projection readers' re-rooting (`elements[i]` / `children[i]`, with
`RangeReferenceStep(i-1, i)` for the i-th element).

The walk names no widget type. `is_focusable_document` is the open trait a
document domain adds a method to: `WidgetModule` marks its enabled interactive
leaves as the Tab stops. Both `LayoutToGraphics` and `WidgetToGraphics` share
the walk for Tab traversal.
"""
module FocusModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..ReferenceModule

export get_first_focusable_path, get_last_focusable_path, get_next_focusable_index,
       is_focusable_document


include("Focus.jl")

end # module
