# Fragment of `InspectorModule` — `ReferenceInspector`, the document that shows
# a reference and what it evaluates to.

@document struct ReferenceInspector
    reference::Union{Nothing, Reference} = nothing
    target::Any = nothing
end
