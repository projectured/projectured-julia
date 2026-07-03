"""
    HoverProbeProjectionModule

A higher-order projection that wraps a window's content projection and, on
idle mouse motion, shows **the reference a single left-click would create at
the pointer** in a secondary follower window.

**Printer** — transparent: projects the wrapped document through `inner` and
returns its output unchanged (so wrapping a document in the probe changes
nothing visually). It remembers the inner iomap so the reader can reuse it.

**Reader** — on a `MouseMove` it reverse-projects the pointer position by
feeding a synthetic `MousePress(:left, x, y)` to the **inner** reader — the
exact path a real click would take — and reads the would-be
`ReplaceSelectionOperation.path` without committing it. It then drives a
follower window (id `id`, `:tooltip` style) via `OpenWindowOperation` /
`CloseWindowOperation`, which `WindowManagingProjection` applies:

- over a clickable glyph → `OpenWindowOperation` carrying a
  `ReferenceInspector(reference, target)` as content, positioned near the
  pointer (`pointer()` + `offset`). Re-issuing the open with the same id
  updates the window in place, so it follows the mouse and refreshes its text.
- over dead space (the probe yields no `ReplaceSelectionOperation`) →
  `CloseWindowOperation`.

Every non-`MouseMove` event passes straight through to `inner`, so real
clicks, keys, scroll, and drags select/edit normally — the probe never
disturbs the document or its selection.

`pointer` is injected (the SDL example wiring passes a closure over the
backend's global mouse position) so this domain projection stays free of any
backend dependency, the same way `TextToGraphics` takes its `measure`.
"""
module HoverProbeProjectionModule

import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward,
                              Projection
import ..IntentModule: Intent
import ..IoMapApiModule: IoMap
import ..MouseModule: MouseMove, MousePress
import ..OperationModule: ReplaceSelectionOperation
import ..ScreenDocumentModule: OpenWindowOperation, CloseWindowOperation
import ..ReferenceInspectorDocumentModule: ReferenceInspector

export HoverProbeProjection, HoverProbeProjectionIoMap

struct HoverProbeProjection <: Projection
    inner::Projection
    id::Symbol
    pointer::Function          # () -> (x, y) global screen coords of the mouse
    offset::Tuple{Int,Int}     # pointer → follower-window offset, in screen px
    size::Tuple{Int,Int}       # follower-window (width, height)
    title::String
    # transient state (Refs so the immutable projection can update them):
    open::Base.RefValue{Bool}
    last::Base.RefValue{Any}
end

"""
    HoverProbeProjection(; inner, pointer, id=:inspector,
                           offset=(16, 20), size=(1000, 400), title="reference")

Wrap `inner` (the content projection whose clicks should be inspected).
`pointer` is a 0-arg callable returning the current global mouse position
`(x, y)` in screen pixels, used to place the follower window.
"""
HoverProbeProjection(; inner::Projection,
                       pointer::Function,
                       id::Symbol = :inspector,
                       offset = (16, 20),
                       size = (1000, 400),
                       title::AbstractString = "reference") =
    HoverProbeProjection(inner, id, pointer,
                         (Int(offset[1]), Int(offset[2])),
                         (Int(size[1]), Int(size[2])), String(title),
                         Ref(false), Ref{Any}(nothing))

struct HoverProbeProjectionIoMap <: IoMap
    projection::HoverProbeProjection
    input::Any
    output::Any
    child_iomap::Any
end

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::HoverProbeProjection, recursion, input, ctx)
    child_iomap = print_document(p.inner, recursion, input, ctx)
    HoverProbeProjectionIoMap(p, input, child_iomap.output, child_iomap)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::HoverProbeProjection, recursion, change::Intent, iomap::HoverProbeProjectionIoMap)
    event = change.gesture
    if event isa MouseMove
        # Reverse-project the hover position exactly as a left click would be.
        press = MousePress(:left, event.x, event.y, event.modifiers)
        probe = read_intent(iomap.child_iomap.projection, recursion,
                                Intent(press, nothing), iomap.child_iomap)
        probe_op = probe isa Intent ? probe.operation : probe
        ref = probe_op isa ReplaceSelectionOperation ? probe_op.path : nothing
        return Intent(change.gesture, _hover_op(p, iomap, ref))
    end
    # Pass everything else through to the wrapped content.
    return read_intent(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)
end

read_intent(p::HoverProbeProjection, iomap::HoverProbeProjectionIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Decide the follower-window operation for a probed reference (or `nothing`).
function _hover_op(p::HoverProbeProjection, iomap::HoverProbeProjectionIoMap, ref)
    if ref === nothing
        if p.open[]
            p.open[] = false
            p.last[] = nothing
            return CloseWindowOperation(p.id)
        end
        return nothing
    end
    (px, py) = p.pointer()
    content = ReferenceInspector(reference = ref, target = iomap.input)
    p.open[] = true
    p.last[] = ref
    return OpenWindowOperation(id = p.id, title = p.title,
                              x = Int(px) + p.offset[1],
                              y = Int(py) + p.offset[2],
                              width = p.size[1], height = p.size[2],
                              style = :tooltip, content = content)
end

# ── Reference mapping (passthrough — the probe is transparent on print) ────

map_reference_forward(::HoverProbeProjection, iomap::HoverProbeProjectionIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(::HoverProbeProjection, iomap::HoverProbeProjectionIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)

end # module
