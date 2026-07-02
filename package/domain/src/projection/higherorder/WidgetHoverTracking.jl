"""
    WidgetHoverTrackingProjectionModule

A **generic** higher-order projection that turns raw pointer motion into
`MouseEnter` / `MouseLeave` crossings and lets the widgets themselves decide
what those mean. It owns *when* the pointer crosses a boundary; each widget owns
*what changes* as a result (a button flips its `hovered`/`pressed` cells, another
widget might do something else entirely). The tracker constructs **no**
widget-specific operation — it only routes enter/leave and forwards whatever
operation the widget returns.

The problem it solves: container hit-test routing delivers a `MouseMove` only to
the child under the pointer, so a widget can learn it was entered but never that
it was left (the leaving move goes to whatever is under the pointer now).

**Printer** — transparent: projects the wrapped document through `inner` and
returns its output unchanged, remembering the inner iomap for the reader.

**Reader** — on each `MouseMove`:

1. Route a synthetic `MouseEnter` at the pointer to `inner`; the widget under the
   pointer answers with an operation identifying itself (an opaque `widget`
   field — the tracker never inspects the operation otherwise).
2. If that target is the same as last time, nothing changed — emit nothing.
3. If it changed, route a synthetic `MouseLeave` to the *previously* entered
   widget (at the last position that was over it) so it can undo its own state,
   and forward both the leave and the enter operations (as a `CompoundOperation`
   when both are present).

Every non-`MouseMove` event passes straight through to `inner`.

Mirrors `HoverProbeProjection` in shape (a transparent wrapper whose reader
reverse-routes the pointer); here the synthesised events are `MouseEnter` /
`MouseLeave` rather than a probe `MousePress`.
"""
module WidgetHoverTrackingProjectionModule

import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward,
                              Projection
import ..ChangeModule: Change, as_change
import ..IoMapApiModule: IoMap
import ..GestureBindingModule: collect_gestures
import ..MouseModule: MouseMove, MouseEnter, MouseLeave
import ..OperationModule: CompoundOperation, ReplaceReferencedValue, ReplaceSelectionOperation
import ..KeyboardModule: KeyDown
# The focus-path helpers live in WidgetModule (document layer), available for the
# top-level Tab wrap-around rule.
import ..WidgetModule: first_focusable_path, last_focusable_path

export WidgetHoverTrackingProjection, WidgetHoverTrackingProjectionIoMap

struct WidgetHoverTrackingProjection <: Projection
    inner::Projection
    # transient state (Refs so the immutable projection can update them):
    last::Base.RefValue{Any}      # identity of the widget currently entered, or nothing
    last_pos::Base.RefValue{Any}  # (x, y) last seen over it, or nothing
end

"""
    WidgetHoverTrackingProjection(; inner)

Wrap `inner` (the widget pipeline whose hover crossings should be tracked).
"""
WidgetHoverTrackingProjection(; inner::Projection) =
    WidgetHoverTrackingProjection(inner, Ref{Any}(nothing), Ref{Any}(nothing))

struct WidgetHoverTrackingProjectionIoMap <: IoMap
    projection::WidgetHoverTrackingProjection
    input::Any
    output::Any
    child_iomap::Any
end

# ── Printer (transparent) ─────────────────────────────────────────────────

function projection_print(p::WidgetHoverTrackingProjection, recursion, input, ctx)
    child_iomap = projection_print(p.inner, recursion, input, ctx)
    WidgetHoverTrackingProjectionIoMap(p, input, child_iomap.output, child_iomap)
end

# ── Reader ────────────────────────────────────────────────────────────────

function projection_read(p::WidgetHoverTrackingProjection, recursion, change::Change,
                         iomap::WidgetHoverTrackingProjectionIoMap)
    event = change.gesture
    # Top-level Tab wrap-around (Stage 2): the only non-local part of focus
    # traversal. Containers advance the selection locally and decline (return
    # nothing) when focus runs off the end of the whole tree. Here, at the outer
    # widget seam, a declined Tab wraps to the first focusable leaf (last for
    # Shift-Tab). Bootstrap (no selection) is handled by the containers themselves,
    # so this only fires for genuine wrap-around. See
    # plan/pending/widget-focus-traversal.md.
    if event isa KeyDown && event.key === :tab
        res = projection_read(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)
        op = res isa Change ? res.operation : res
        op === nothing || return res
        root = iomap.child_iomap.input
        wrap = event.modifiers.shift ? last_focusable_path(root) : first_focusable_path(root)
        return Change(event, wrap === nothing ? nothing : ReplaceSelectionOperation(wrap))
    end
    event isa MouseMove || return projection_read(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)

    child = iomap.child_iomap
    # 0. Forward the real MouseMove down the inner pipeline first, so widgets
    #    that legitimately consume MouseMove (e.g. an active splitter drag in
    #    WidgetSplitPane) get a chance to react. Hover enter/leave synthesis
    #    runs afterwards and its ops are merged in with the inner result.
    inner_res = projection_read(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)
    inner_op  = inner_res isa Change ? inner_res.operation : inner_res

    # 1. Who is under the pointer now? Route an enter and read back the widget's
    #    own response; its `widget` field is an opaque identity token.
    enter_op = _route(p, recursion, child, MouseEnter(event.x, event.y, event.buttons, event.modifiers))
    new_target = _target_of(enter_op)
    old_target = p.last[]

    if new_target === old_target
        # Same widget (or both dead space): keep the inside position fresh so a
        # future leave is routed at a point still over the target.
        new_target === nothing || (p.last_pos[] = (event.x, event.y))
        return Change(event, inner_op)
    end

    ops = Any[]
    # 2. Leave the previously entered widget, at the last position over it, so it
    #    undoes its own state. We forward whatever it returns; we never build it.
    if old_target !== nothing && p.last_pos[] !== nothing
        ox, oy = p.last_pos[]
        leave_op = _route(p, recursion, child, MouseLeave(ox, oy, event.buttons, event.modifiers))
        leave_op === nothing || push!(ops, leave_op)
    end
    # 3. Enter the new widget (forward the response we already have).
    new_target === nothing || enter_op === nothing || push!(ops, enter_op)
    # 4. Merge in the inner pipeline's response to the MouseMove itself.
    inner_op === nothing || push!(ops, inner_op)

    p.last[] = new_target
    p.last_pos[] = new_target === nothing ? nothing : (event.x, event.y)
    Change(event, isempty(ops) ? nothing : length(ops) == 1 ? ops[1] : CompoundOperation(ops))
end

# 3-arg compatibility shim (tests / hit-test recursion).
projection_read(p::WidgetHoverTrackingProjection, iomap::WidgetHoverTrackingProjectionIoMap, payload) =
    projection_read(p, nothing, as_change(payload), iomap).operation

# Route a synthetic event through the inner pipeline and return the bare op.
function _route(p::WidgetHoverTrackingProjection, recursion, child_iomap, event)
    res = projection_read(child_iomap.projection, recursion, Change(event, nothing), child_iomap)
    res isa Change ? res.operation : res
end

# Opaque identity of the widget an enter-response came from. The tracker never
# interprets the operation beyond this token, so it stays agnostic of any widget's
# concrete hover/press operations: a legacy widget-identity op exposes it as
# `.widget`; an identity-rooted `ReplaceReferencedValue` (the folded hover/press
# write) carries its target widget as the root `.document`.
function _target_of(op)
    op === nothing && return nothing
    op isa ReplaceReferencedValue && return op.document
    hasproperty(op, :widget) ? op.widget : nothing
end

# ── Reference mapping (passthrough — the tracker is transparent on print) ──

map_reference_forward(::WidgetHoverTrackingProjection, iomap::WidgetHoverTrackingProjectionIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(::WidgetHoverTrackingProjection, iomap::WidgetHoverTrackingProjectionIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)

# Gesture collection is transparent too: the tracker adds no gestures of its own,
# so F1 help must see the wrapped pipeline's gestures. Without this the default
# leaf `collect_gestures` would stop at the tracker (it only knows the root
# document), and wrapping a whole pipeline in the tracker would hide every gesture
# below it (cf. the SequentialProjection / RecursiveProjection combinator methods).
collect_gestures(::WidgetHoverTrackingProjection, recursion, iomap::WidgetHoverTrackingProjectionIoMap) =
    collect_gestures(iomap.child_iomap.projection, recursion, iomap.child_iomap)

end # module
