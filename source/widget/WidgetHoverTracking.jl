# Fragment of `WidgetModule`.
#
# A **generic** higher-order projection that turns raw pointer motion into
# `MouseEnter` / `MouseLeave` crossings and lets the widgets themselves decide
# what those mean. It owns *when* the pointer crosses a boundary; each widget owns
# *what changes* as a result (a button flips its `hovered`/`pressed` cells, another
# widget might do something else entirely). The tracker constructs **no**
# widget-specific operation — it only routes enter/leave and forwards whatever
# operation the widget returns.
#
# The problem it solves: container hit-test routing delivers a `MouseMove` only to
# the child under the pointer, so a widget can learn it was entered but never that
# it was left (the leaving move goes to whatever is under the pointer now).
#
# **Printer** — transparent: projects the wrapped document through `inner` and
# returns its output unchanged, remembering the inner iomap for the reader.
#
# **Reader** — on each `MouseMove`:
#
# 1. Route a synthetic `MouseEnter` at the pointer to `inner`; the widget under the
#    pointer answers with an operation identifying itself (an opaque `widget`
#    field — the tracker never inspects the operation otherwise).
# 2. If that target is the same as last time, nothing changed — emit nothing.
# 3. If it changed, route a synthetic `MouseLeave` to the *previously* entered
#    widget (at the last position that was over it) so it can undo its own state,
#    and forward both the leave and the enter operations (as a `CompoundOperation`
#    when both are present).
#
# Every non-`MouseMove` event passes straight through to `inner`.
#
# Mirrors `HoverProbeProjection` in shape (a transparent wrapper whose reader
# reverse-routes the pointer); here the synthesised events are `MouseEnter` /
# `MouseLeave` rather than a probe `MousePress`.
# The generic focus walk, for the top-level Tab wrap-around rule.


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

# Transparent: `output` forwards the child's output through a cell so the IoMap
# keeps its identity while the child re-derives (PAR-STABLE-IOMAP-IDENTITY).
@iomap struct WidgetHoverTrackingIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::WidgetHoverTrackingProjection, recursion, input, ctx)
    child_iomap = print_document(p.inner, recursion, input, ctx)
    WidgetHoverTrackingIoMap(p, input, ComputedCell(() -> child_iomap.output), child_iomap)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::WidgetHoverTrackingProjection, recursion, change::Intent,
                         iomap::WidgetHoverTrackingIoMap)
    event = change.gesture
    # Top-level Tab wrap-around (Stage 2): the only non-local part of focus
    # traversal. Containers advance the selection locally and decline (return
    # nothing) when focus runs off the end of the whole tree. Here, at the outer
    # widget seam, a declined Tab wraps to the first focusable leaf (last for
    # Shift-Tab). Bootstrap (no selection) is handled by the containers themselves,
    # so this only fires for genuine wrap-around. See
    # plan/done/widget-focus-traversal.md.
    if event isa KeyDown && event.key === :tab
        res = read_intent(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)
        op = res isa Intent ? res.operation : res
        op === nothing || return res
        root = iomap.child_iomap.input
        wrap = event.modifiers.shift ? get_last_focusable_path(root) : get_first_focusable_path(root)
        return Intent(event, wrap === nothing ? nothing : ReplaceSelectionOperation(wrap))
    end
    event isa MouseMove || return read_intent(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)

    child = iomap.child_iomap
    # 0. Forward the real MouseMove down the inner pipeline first, so widgets
    #    that legitimately consume MouseMove (e.g. an active splitter drag in
    #    WidgetSplitPane) get a chance to react. Hover enter/leave synthesis
    #    runs afterwards and its ops are merged in with the inner result.
    inner_res = read_intent(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)
    inner_op  = inner_res isa Intent ? inner_res.operation : inner_res

    # 1. Who is under the pointer now? Route an enter and read back the widget's
    #    own response; its `widget` field is an opaque identity token.
    enter_op = _route(p, recursion, child, MouseEnter(event.x, event.y, event.buttons, event.modifiers))
    new_target = _target_of(enter_op)
    old_target = p.last[]

    if new_target === old_target
        # Same widget (or both dead space): keep the inside position fresh so a
        # future leave is routed at a point still over the target.
        new_target === nothing || (p.last_pos[] = (event.x, event.y))
        return Intent(event, inner_op)
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
    Intent(event, isempty(ops) ? nothing : length(ops) == 1 ? ops[1] : CompoundOperation(ops))
end

# 3-arg payload form (tests / hit-test recursion).
read_intent(p::WidgetHoverTrackingProjection, iomap::WidgetHoverTrackingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Route a synthetic event through the inner pipeline and return the bare op.
function _route(p::WidgetHoverTrackingProjection, recursion, child_iomap, event)
    res = read_intent(child_iomap.projection, recursion, Intent(event, nothing), child_iomap)
    res isa Intent ? res.operation : res
end

# Opaque identity of the widget an enter-response came from. The tracker never
# interprets the operation beyond this token, so it stays agnostic of any widget's
# concrete hover/press operations: a widget-identity op exposes it as
# `.widget`; an identity-rooted `ReplaceReferencedValueOperation` (the folded hover/press
# write) carries its target widget as the root `.document`.
function _target_of(op)
    op === nothing && return nothing
    # A history around the widget records its answer, and a hover write is marked
    # as view state: the widget is inside either wrapper.
    op isa WrappingOperation && return _target_of(get_wrapped_operation(op))
    op isa ReplaceReferencedValueOperation && return op.document
    hasproperty(op, :widget) ? op.widget : nothing
end

# ── Reference mapping (passthrough — the tracker is transparent on print) ──

map_reference_forward(::WidgetHoverTrackingProjection, iomap::WidgetHoverTrackingIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(::WidgetHoverTrackingProjection, iomap::WidgetHoverTrackingIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)
