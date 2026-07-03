"""
    GestureMapModule

A read-only document listing the gesture bindings available in some context — the
rendered face of the reified `GestureBinding` data. Each [`GestureRow`](@ref)
pairs a gesture rendering (`describe(pattern)`) with what it does and whether it
is currently applicable; [`GestureMapToSyntax`](../projection/primitive/GestureMapToSyntax.jl)
projects a `GestureMap` onto the existing Syntax → Text → Graphics pipeline so the
help window reuses the normal display path.

Build one from a binding list and the document the bindings act on (applicability
is evaluated against that document's current selection):

    gesture_map(collect_gesture_bindings(pipeline, recursion, iomap), focused_doc)
    gesture_map(get_document_gesture_bindings(JsonObject), some_object)   # global, by type
"""
module GestureMapModule

import ..ReactiveModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference
import ..GestureBindingModule: GestureBinding, describe

export GestureMap, GestureRow, gesture_map

"""
    GestureRow(gesture, description, domain, applicable)

One display row: `gesture` is the keystroke/click rendering (`describe(pattern)`),
`description` is what it does, `domain` groups rows under a heading, and
`applicable` is whether the binding can fire for the current selection (greyed
when false).
"""
struct GestureRow
    gesture::String
    description::String
    domain::String
    applicable::Bool
end

"""
    GestureMap(rows = GestureRow[])

A document wrapping the gesture rows for display. Read-only: it carries the
`selection` field the `Document` contract requires, but no editing gestures of
its own.
"""
@document struct GestureMap
    rows::Any = GestureRow[]
    selection::Reference = nothing
end

# Evaluate a binding's precondition defensively: a collector spanning several
# domains may carry bindings whose `applicable` does not accept this document, in
# which case the row is simply shown as not-applicable rather than erroring.
_row_applicable(b::GestureBinding, doc, sel) = try b.applicable(doc, sel) catch; false end

"""
    gesture_map(bindings, doc) -> GestureMap

Turn `bindings` into a `GestureMap`, marking each row applicable when its
precondition holds for `doc`'s current selection.
"""
function gesture_map(bindings, doc)
    sel = getfield(doc, :selection)[]
    rows = GestureRow[GestureRow(describe(b.pattern), b.description, b.domain,
                                 _row_applicable(b, doc, sel)) for b in bindings]
    GestureMap(rows, nothing)
end

end # module
