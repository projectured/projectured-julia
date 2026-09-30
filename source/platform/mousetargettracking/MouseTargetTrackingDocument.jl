# Fragment of `MouseTargetTrackingModule` — the state of the tracking, a document
# that wraps the document that the projection shows.

# Where the pointer was last: the window, the point in it, and what it held.
struct _Position
    window::Union{Symbol,Nothing}
    x::Int
    y::Int
    buttons::MouseButtons
    modifiers::ModifierKeys
end

# A crossing that waits for the content: the gesture, and the route to its part.
struct _Crossing
    route::Reference
    gesture::Gesture
end

"""
    MouseTargetTrackingState(; content)

The state of the target tracking, around `content`. A view state operation
writes each field, so a history does not record it:

- `target` — the path of the part under the pointer, from `content`, without a
  point step at its end, or `nothing`;
- `parts` — the prefixes of `target` that name a document, the outer first: the
  parts that the pointer is on;
- `position` — where the pointer was last, or `nothing` after it left;
- `waiting` — the crossings that wait for the content, in order.

The values are immutable, so each write replaces a whole value.
"""
@document struct MouseTargetTrackingState <: Document
    content::Document
    target::Any = nothing
    parts::Any = ()
    position::Any = nothing
    waiting::Any = ()
end

get_wrapped_document(state::MouseTargetTrackingState) = get_wrapped_document(state.content)
