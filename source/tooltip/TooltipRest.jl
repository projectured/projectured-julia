# Fragment of `TooltipModule` — when a tooltip opens: once the pointer has rested
# on something for a moment, and not while it moves.
#
# **A resting pointer sends nothing.** The backend holds back idle motion and sends
# the last position once, so no event arrives while the pointer rests, and a
# reader can not see a rest by itself. The time comes from the editor's loop
# instead: a feed names a deadline, the loop sleeps until it, and at the deadline
# the feed reads a `PointerRest` gesture through the editor's own projection. The
# probe answers it; every other reader declines a gesture it does not know.

"""
    PointerRest(x, y; time)
    PointerRest(x, y, time)

The pointer has rested at `(x, y)`, in the frame of the window it is in, for as
long as a tooltip waits. A [`TooltipFeed`](@ref) reads it through the editor's
projection when its deadline passes, with the time of that moment, and a
`TooltipProbeProjection` answers it.
"""
struct PointerRest <: Gesture
    x::Int
    y::Int
    time::Float64
end

PointerRest(x::Int, y::Int; time::Real) = PointerRest(x, y, Float64(time))

"""
    TooltipRest()

Where the pointer last moved and when, and whether a tooltip is shown. A probe
writes it on every event, and the feed of the same window reads it to name its
deadline, so the two share one.
"""
mutable struct TooltipRest
    x::Int
    y::Int
    # The time of the last move that no rest has answered yet, or `nothing`.
    moved_at::Union{Nothing,Float64}
    shown::Bool
    # Where the pointer rested when the tooltip opened, which a move away from
    # closes it.
    shown_x::Int
    shown_y::Int
end

TooltipRest() = TooltipRest(0, 0, nothing, false, 0, 0)

"""
    TooltipFeed

The time a tooltip waits. It names a deadline — the last move plus `delay` —
while a move is waiting and no tooltip is shown, and nothing otherwise, so an
idle window sleeps. At the deadline it reads a [`PointerRest`](@ref) through the
editor's projection and posts the operation that comes back.

Make it with [`make_tooltip_feed`](@ref) and hand the same feed to the fold and
to `run_window_editor(feeds = …)`.
"""
struct TooltipFeed <: Feed
    rest::TooltipRest
    delay::Float64
    now::Function
    window::Union{Nothing,Symbol}
end

"""
    make_tooltip_feed(; delay = 0.5, now = time, window = nothing) -> TooltipFeed

A feed that opens a tooltip `delay` seconds after the pointer stops. `now` answers
the time in seconds, and a test hands its own. `window` is the id of the window
the probe sits in; `nothing` means the first window of the screen.
"""
make_tooltip_feed(; delay::Real = 0.5, now::Function = time,
                    window::Union{Nothing,Symbol} = nothing) =
    TooltipFeed(TooltipRest(), Float64(delay), now, window)

# How many seconds until the tooltip is due, or `nothing` when none is waiting.
function _find_rest_deadline(feed::TooltipFeed)
    rest = feed.rest
    (rest.moved_at === nothing || rest.shown) && return nothing
    max(0.0, rest.moved_at + feed.delay - feed.now())
end

compute_wake_deadline(feed::TooltipFeed, editor) = _find_rest_deadline(feed)

function drain_changes!(feed::TooltipFeed, editor)
    deadline = _find_rest_deadline(feed)
    (deadline === nothing || deadline > 0) && return 0
    rest = feed.rest
    rest.moved_at = nothing
    editor.iomap === nothing && return 0
    window = something(feed.window, first(editor.document.windows).id)
    gesture = PointerRest(rest.x, rest.y; time = time())
    change = read_intent(editor.projection, nothing,
                         Intent(WindowInput(window, gesture), nothing), editor.iomap)
    operation = change isa Intent ? change.operation : change
    operation isa Operation || return 0
    post_operation!(editor, operation)
    1
end
