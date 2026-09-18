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

# The hover probe fills `reference` and `target` as the pointer moves, so what
# they hold is a moment, not data. A save writes nothing, and a load gets an
# inspector that fills again the next time the pointer moves.
pred_arguments(::ReferenceInspector) = (), Pair{Symbol,Any}[]
