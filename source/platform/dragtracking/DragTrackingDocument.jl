# Fragment of `DragTrackingModule` — the state of the drag, a document that wraps
# the document that the projection shows.

"""
    DragTrackingState(; content)

The state of the drag tracking, around `content`. A view state operation writes
each field, so a history does not record it:

- `drag_path` — the path in `content` of the part whose drag is on, or `nothing`
  when no drag is on;
- `dragged` — the thing that a global drag carries, or `nothing` for a local
  drag.
"""
@document struct DragTrackingState <: Document
    content::Document
    drag_path::Any = nothing
    dragged::Any = nothing
end

get_wrapped_document(state::DragTrackingState) = get_wrapped_document(state.content)
