# ──────────────────────────────────────────────────────────────────────────
# Folded in from DraggingWrapper.jl.
using ProjecturedProjection.NestingProjectionModule: NestingProjection


"""
    make_dragging_document(document; threshold = 5) -> DraggingState

Wrap a document so a press that travels `threshold` pixels becomes a drag and a
drop reorders the collection under the grab point. The wrapper is transparent to
the printer, so the content renders as it did.
"""
make_dragging_document(document; threshold::Int = 5) = DraggingState(document, threshold)

"""
    make_dragging_projection(projection) -> Projection

The projection half of the same wrapper.
"""
make_dragging_projection(projection) =
    NestingProjection(DraggingProjection(); recursion = projection)
