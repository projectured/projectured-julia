# Fragment of `GestureTrackingModule` — the state of the recognition, a document
# that wraps the document that the projection shows.

# A button that went down, and where and when: the start of a click.
struct _ButtonPress
    button::Symbol
    window_id::Symbol
    x::Int
    y::Int
    time::Float64
end

# The last click: the start of a double click.
struct _Click
    button::Symbol
    window_id::Symbol
    x::Int
    y::Int
    time::Float64
    count::Int
end

# The last motion of the pointer with no button held, which a dwell waits after.
struct _Motion
    window_id::Symbol
    x::Int
    y::Int
    modifiers::ModifierKeys
    time::Float64
end

"""
    GestureTrackingState(; content)

The state of the gesture tracking, around `content`. A view state operation
writes each field, so a history does not record it:

- `presses` — the buttons that are down, each with the place and the time of its
  down, until its up;
- `last_click` — the last click, for the count of a double or a triple click;
- `chord_keys` — the keys of a chord that is not complete yet;
- `waiting` — the gestures and the events that wait for the content, in order;
- `motion` — the last motion of the pointer with no button held, while a dwell
  can still follow it.

The values are immutable, so each write replaces a whole value.
"""
@document struct GestureTrackingState <: Document
    content::Document
    presses::Any = ()
    last_click::Any = nothing
    chord_keys::Any = ()
    waiting::Any = ()
    motion::Any = nothing
end

get_wrapped_document(state::GestureTrackingState) = get_wrapped_document(state.content)
