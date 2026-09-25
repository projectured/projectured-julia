# Fragment of `TooltipModule` — the probe that shows what the thing under the
# pointer says about itself, once the pointer has rested on it.
#
# **Printer** — transparent: it projects the wrapped document through `inner` and
# answers that output, so wrapping a window in the probe changes nothing drawn.
#
# **Reader** — every event goes to the inner reader first, exactly as it would
# without the probe: a hover, a drag and a click need the pointer, and the probe
# only watches it. A move notes where the pointer is and when, in the
# `TooltipRest` it shares with the window's `TooltipFeed`; a move away from an
# open tooltip, a press, a key and a scroll close it. When the feed's deadline
# passes it reads a `PointerRest`, and only then does the probe look: it feeds the
# inner reader a synthetic **Alt+left press**, which selects whatever is under the
# pointer as a whole, reads the path back without committing it, and asks
# `compute_tooltip` what that document says. What comes back opens a window of
# its own, beside the pointer.
#
# **Alt, and not a plain press.** A plain press is a widget's own gesture: a
# button answers its action. An Alt press answers a selection and never an
# action, so a probe that never commits what it reads still cannot be the thing
# that makes an action fire.

struct TooltipProbeProjection <: Projection
    inner::Projection
    id::Symbol
    compute_tooltip::Function  # (document) -> Document | Nothing
    pointer::Function          # () -> (x, y), the pointer in screen coordinates
    offset::Tuple{Int,Int}     # pointer -> window offset, in screen pixels
    minimum_size::Tuple{Int,Int}   # the window never gets smaller than this
    maximum_size::Tuple{Int,Int}   # it is printed at this, and never grows past it
    title::String
    rest::TooltipRest          # shared with the window's `TooltipFeed`
    now::Function              # () -> seconds, the feed's own clock
    slop::Int                  # how far the pointer may move before it closes
end

"""
    TooltipProbeProjection(; inner, compute_tooltip, pointer, feed,
                             id = :tooltip, offset = (16, 20),
                             minimum_size = (120, 32), maximum_size = (560, 400),
                             title = "tooltip", slop = 4)

Wrap `inner`, the content projection of the window whose documents should answer
for themselves.

`compute_tooltip` is `(document) -> Document | Nothing`. A host passes the
generic of that name, which every document answers; a host that wants another
rule passes another function, and this slice needs no dependency on the slices
that answer it.

`pointer` is a 0-argument callable answering the pointer in **screen**
coordinates, which is where a window is placed. `get_pointer_position` of the SDL
backend answers exactly that.

`feed` is the window's [`TooltipFeed`](@ref): the probe tells it where the pointer
is and when it moved, and the feed says when the pointer has rested. A move of
more than `slop` pixels from where a tooltip opened closes it.

**The window fits what it holds.** It is printed at `maximum_size`, so a text
wraps at that width, and it ends with the extent of what it printed, never
smaller than `minimum_size`. The backend keeps it on the screen.
"""
TooltipProbeProjection(; inner::Projection,
                         compute_tooltip::Function,
                         pointer::Function,
                         feed::TooltipFeed,
                         id::Symbol = :tooltip,
                         offset = (16, 20),
                         minimum_size = (120, 32),
                         maximum_size = (560, 400),
                         title::AbstractString = "tooltip",
                         slop::Integer = 4) =
    TooltipProbeProjection(inner, id, compute_tooltip, pointer,
                           (Int(offset[1]), Int(offset[2])),
                           (Int(minimum_size[1]), Int(minimum_size[2])),
                           (Int(maximum_size[1]), Int(maximum_size[2])), String(title),
                           feed.rest, feed.now, Int(slop))

@iomap struct TooltipProbeIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::TooltipProbeProjection, recursion, input, ctx)
    child_iomap = print_document(p.inner, recursion, input, ctx)
    TooltipProbeIoMap(p, input, Cell(@computation child_iomap.output), child_iomap)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::TooltipProbeProjection, recursion, change::Intent,
                     iomap::TooltipProbeIoMap)
    event = change.gesture
    event isa PointerRest && return Intent(event, _open_at_rest(p, recursion, iomap, event))
    answer = read_intent(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)
    own = _follow_pointer!(p, event)
    own === nothing && return answer
    inner = answer isa Intent ? answer.operation : answer
    Intent(event, inner isa Operation ? CompoundOperation(Any[inner, own]) : own)
end

read_intent(p::TooltipProbeProjection, iomap::TooltipProbeIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Note where the pointer is. A move without a button starts the wait again; a move
# with one is a drag and no rest. A move away from an open tooltip, a press, a
# down, a key and a scroll close it.
function _follow_pointer!(p::TooltipProbeProjection, event)
    rest = p.rest
    if event isa MouseMove
        if event.buttons == MouseButtons()
            rest.x = event.x
            rest.y = event.y
            rest.moved_at = p.now()
        else
            rest.moved_at = nothing
        end
        away = abs(event.x - rest.shown_x) + abs(event.y - rest.shown_y) > p.slop
        return rest.shown && away ? _close_tooltip!(p) : nothing
    elseif event isa Union{MousePress,MouseDown,KeyDown,KeyPress,MouseScroll}
        rest.moved_at = nothing
        return rest.shown ? _close_tooltip!(p) : nothing
    end
    nothing
end

function _close_tooltip!(p::TooltipProbeProjection)
    p.rest.shown = false
    CloseWindowOperation(p.id)
end

# The pointer has rested: look once at what is under it, and open a window with
# what it says. A document that says nothing opens none.
function _open_at_rest(p::TooltipProbeProjection, recursion, iomap::TooltipProbeIoMap,
                       event::PointerRest)
    rest = p.rest
    rest.moved_at = nothing
    rest.shown && return nothing
    press = MousePress(:left, event.x, event.y, ModifierKeys(alt = true);
                       time = event.time)
    probe = read_intent(iomap.child_iomap.projection, recursion,
                        Intent(press, nothing), iomap.child_iomap)
    operation = probe isa Intent ? probe.operation : probe
    path = operation isa ReplaceSelectionOperation ? operation.path : nothing
    node = path === nothing ? nothing : try_evaluate_reference(iomap.input, path, nothing)
    content = node === nothing ? nothing : p.compute_tooltip(node)
    content === nothing && return nothing
    (x, y) = p.pointer()
    rest.shown = true
    rest.shown_x = event.x
    rest.shown_y = event.y
    OpenWindowOperation(id = p.id, title = p.title,
                        x = Int(x) + p.offset[1], y = Int(y) + p.offset[2],
                        width = p.maximum_size[1], height = p.maximum_size[2],
                        minimum_size = p.minimum_size, maximum_size = p.maximum_size,
                        style = :tooltip, content = content)
end

# ── Reference mapping (passthrough — the probe is transparent on print) ────

map_reference_forward(::TooltipProbeProjection, iomap::TooltipProbeIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(::TooltipProbeProjection, iomap::TooltipProbeIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)
