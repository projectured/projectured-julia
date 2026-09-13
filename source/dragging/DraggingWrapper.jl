# ──────────────────────────────────────────────────────────────────────────
# Folded in from DraggingWrapper.jl.
#
# ── Applying the wrapper ────────────────────────────────────────────────────
#
# A wrapper is a `(document, projection)` pair of transforms, applied in a fixed
# order where later sits further out. These two are dragging's half of that, and
# they live here rather than in the gallery because the types they name are this
# package's. They were `ProjecturedWorkbenchExample`'s until stage 14 of
# omnet-julia's build-programs plan, which is a package of 52 dependencies —
# so a program could not drag without the whole example tier for two lines.
using ProjecturedProjection.ProjectionAlgebraModule: NestingProjection


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
