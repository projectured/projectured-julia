# Fragment of `TooltipModule` — the probe that shows what the thing under the
# pointer says about itself.
#
# **Printer** — transparent: it projects the wrapped document through `inner` and
# answers that output, so wrapping a window in the probe changes nothing drawn.
#
# **Reader** — on a `MouseMove` it reverse-projects the pointer by feeding the
# inner reader a synthetic **Alt+left press**, which is the gesture that selects
# whatever is under the pointer as a whole. It reads the path back without
# committing it, resolves it, and asks `find_tooltip` what that document says.
# What comes back opens a window of its own, beside the pointer.
#
# **Alt, and not a plain press.** A plain press is a widget's own gesture: a
# button answers its action. An Alt press answers a selection and never an
# action, so a probe that never commits what it reads still cannot be the thing
# that makes an action fire.
#
# **What plays the part of a dwell.** The probe opens when the ANSWER changes,
# not on every move, so a pointer crossing a wide label re-opens nothing. The
# delay before the first one is the backend's own idle-motion interval — SDL
# already throttles motion it considers idle — so this projection keeps no clock
# and stays a pure reader.

struct TooltipProbeProjection <: Projection
    inner::Projection
    id::Symbol
    find_tooltip::Function     # (document) -> Document | Nothing
    pointer::Function          # () -> (x, y), the pointer in screen coordinates
    offset::Tuple{Int,Int}     # pointer -> window offset, in screen pixels
    size::Tuple{Int,Int}       # the window's (width, height)
    title::String
    # transient state (Refs, so the immutable projection can update them):
    open::Base.RefValue{Bool}
    last::Base.RefValue{Any}   # the document the open tooltip speaks about
end

"""
    TooltipProbeProjection(; inner, find_tooltip, pointer, id = :tooltip,
                             offset = (16, 20), size = (420, 120),
                             title = "tooltip")

Wrap `inner`, the content projection of the window whose documents should answer
for themselves.

`find_tooltip` is `(document) -> Document | Nothing`. A host passes
`compute_tooltip`, the generic every document answers; a host that wants another
rule passes another function, and this slice needs no dependency on the slices
that answer it.

`pointer` is a 0-argument callable answering the pointer in **screen**
coordinates, which is where a window is placed. `get_pointer_position` of the SDL
backend answers exactly that.
"""
TooltipProbeProjection(; inner::Projection,
                         find_tooltip::Function,
                         pointer::Function,
                         id::Symbol = :tooltip,
                         offset = (16, 20),
                         size = (420, 120),
                         title::AbstractString = "tooltip") =
    TooltipProbeProjection(inner, id, find_tooltip, pointer,
                           (Int(offset[1]), Int(offset[2])),
                           (Int(size[1]), Int(size[2])), String(title),
                           Ref(false), Ref{Any}(nothing))

@iomap struct TooltipProbeIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::TooltipProbeProjection, recursion, input, ctx)
    child_iomap = print_document(p.inner, recursion, input, ctx)
    TooltipProbeIoMap(p, input, ComputedCell(() -> child_iomap.output), child_iomap)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::TooltipProbeProjection, recursion, change::Intent,
                     iomap::TooltipProbeIoMap)
    event = change.gesture
    event isa MouseMove ||
        return read_intent(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)
    press = MousePress(:left, event.x, event.y, ModifierKeys(alt = true))
    probe = read_intent(iomap.child_iomap.projection, recursion,
                        Intent(press, nothing), iomap.child_iomap)
    operation = probe isa Intent ? probe.operation : probe
    path = operation isa ReplaceSelectionOperation ? operation.path : nothing
    Intent(change.gesture, _tooltip_operation(p, iomap, path))
end

read_intent(p::TooltipProbeProjection, iomap::TooltipProbeIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# What the probe found, and what to do about it. A path that resolves to a
# document whose answer is a document opens a window; anything else closes one.
function _tooltip_operation(p::TooltipProbeProjection, iomap::TooltipProbeIoMap, path)
    node = path === nothing ? nothing :
           try_evaluate_reference(iomap.input, path, nothing)
    content = node === nothing ? nothing : p.find_tooltip(node)
    if content === nothing
        p.open[] || return nothing
        p.open[] = false
        p.last[] = nothing
        return CloseWindowOperation(p.id)
    end
    # The same document under the pointer says the same thing, so say it once.
    p.open[] && p.last[] === node && return nothing
    (x, y) = p.pointer()
    p.open[] = true
    p.last[] = node
    OpenWindowOperation(id = p.id, title = p.title,
                        x = Int(x) + p.offset[1], y = Int(y) + p.offset[2],
                        width = p.size[1], height = p.size[2],
                        style = :tooltip, content = content)
end

# ── Reference mapping (passthrough — the probe is transparent on print) ────

map_reference_forward(::TooltipProbeProjection, iomap::TooltipProbeIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(::TooltipProbeProjection, iomap::TooltipProbeIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)
