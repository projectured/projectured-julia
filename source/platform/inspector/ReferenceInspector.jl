# Fragment of `InspectorModule` — `ReferenceInspector`, the document that shows
# a reference and what it evaluates to.

@document struct ReferenceInspector
    reference::Union{Nothing, Reference} = nothing
    target::Any = nothing
end

# The name the tab calls itself, and the name a person types into an empty tab
# to open one.
get_document_title(::ReferenceInspector) = "Reference"
get_insertion_aliases(::Type{ReferenceInspector}) = ["reference"]

# `reference` and `target` are set from outside — a `SelectionInspectorToText`
# following a selection, a caller building one directly — so what they hold is
# a moment, not data. A save writes nothing, and a load gets an inspector with
# no reference until something sets it.
pred_arguments(::ReferenceInspector) = (), Pair{Symbol,Any}[]
