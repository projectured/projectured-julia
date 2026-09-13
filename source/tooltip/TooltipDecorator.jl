# ──────────────────────────────────────────────────────────────────────────
# Folded in from TooltipDecorator.jl.
#
# A higher-order projection that dispatches on `TooltipSource` documents.
#
# **Printer** — transparent: projects `source.child` through the outer
# recursion and returns its output. The `TooltipSource` itself contributes
# nothing to the visual output.
#
# **Reader** — runs a small per-source state machine each time it sees an
# event. The `trigger` callback decides whether the tooltip should
# currently be visible; transitions emit `OpenWindowOperation` /
# `CloseWindowOperation`, which bubble up to `WindowManagingProjection`.
#
# State (arm-time / is-open) is held per `source.id` on the projection
# instance, so a single decorator instance can handle multiple sibling
# sources independently.
# Transparent: `output` forwards the child's output through a cell so the IoMap
# keeps its identity while the child re-derives (PAR-STABLE-IOMAP-IDENTITY).
@iomap struct TooltipDecoratorIoMap
    projection::Any
    input::Any              # TooltipSource
    output::Any             # whatever child projects to
    child_iomap::Any
end

"""
    TooltipDecoratorProjection(; trigger, position=default_position,
                                 title="", delay_ms=0)

A projection over `TooltipSource`.

- `trigger::Function` — `(source, event) -> Bool`. Called for every
  event reaching the reader. When the return flips from `false` to
  `true` (and the delay has elapsed) the decorator emits an
  `OpenWindowOperation`; when it flips back the decorator emits a
  `CloseWindowOperation`.
- `position::Function` — `(source) -> (x, y, width, height)`. Called at
  open time. Defaults to a fixed off-corner placement; in practice
  callers will supply something derived from the iomap geometry.
- `title::AbstractString` — forwarded into `OpenWindowOperation.title`.
- `delay_ms::Integer` — milliseconds the trigger must remain true
  before the open fires. `0` opens on the first event where the
  trigger is true.
"""
struct TooltipDecoratorProjection <: Projection
    trigger::Function
    position::Function
    title::String
    delay_ms::Int
    state::Dict{Symbol, Tuple{Union{Nothing,Float64}, Bool}}
end

default_tooltip_position(_source) = (0, 0, 400, 200)

TooltipDecoratorProjection(; trigger::Function,
                              position::Function = default_tooltip_position,
                              title::AbstractString = "",
                              delay_ms::Integer = 0) =
    TooltipDecoratorProjection(trigger, position, String(title), Int(delay_ms),
                                Dict{Symbol, Tuple{Union{Nothing,Float64}, Bool}}())

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::TooltipDecoratorProjection, recursion, input::TooltipSource, ctx)
    child_iomap = print_child(recursion, input.child, ctx)
    TooltipDecoratorIoMap(p, input, ComputedCell(() -> child_iomap.output), child_iomap)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::TooltipDecoratorProjection, recursion, change::Intent, iomap::TooltipDecoratorIoMap)
    event = change.gesture
    child_op = read_intent(iomap.child_iomap.projection, recursion, change, iomap.child_iomap).operation

    source = iomap.input::TooltipSource
    fired = p.trigger(source, event)::Bool

    sid = source.id
    arm_time, is_open = get(p.state, sid, (nothing, false))
    cur_time = time()

    if fired
        arm_time === nothing && (arm_time = cur_time)
    else
        arm_time = nothing
    end

    decorator_op = nothing
    if fired && !is_open && arm_time !== nothing && (cur_time - arm_time) * 1000 >= p.delay_ms
        (x, y, w, h) = p.position(source)
        decorator_op = OpenWindowOperation(
            id      = source.id,
            title   = p.title,
            x       = x, y = y,
            width   = w, height = h,
            style   = source.style,
            content = source.content,
        )
    elseif !fired && is_open
        decorator_op = CloseWindowOperation(source.id)
    end

    # Child has priority — if it produced an op, return that and let the
    # tooltip transition wait for the next event. State is committed only
    # when the decorator op is actually emitted, so the next event will
    # re-attempt the same transition.
    if decorator_op !== nothing && !(child_op isa Operation)
        if decorator_op isa OpenWindowOperation
            is_open = true
        elseif decorator_op isa CloseWindowOperation
            is_open = false
        end
        p.state[sid] = (arm_time, is_open)
        return Intent(change.gesture, decorator_op)
    end

    p.state[sid] = (arm_time, is_open)
    return Intent(change.gesture, child_op)
end

read_intent(p::TooltipDecoratorProjection, iomap::TooltipDecoratorIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping ────────────────────────────────────────────────────
# The decorator's output is the child's output (the TooltipSource's
# `content` / `style` / `id` fields contribute nothing visible), so
# output-side references look exactly like the child's. Input-side
# references go through the TooltipSource and need a `FieldReferenceStep("child")`
# step to reach the wrapped node.

function map_reference_forward(::TooltipDecoratorProjection, iomap::TooltipDecoratorIoMap, reference)
    # Strip a leading FieldReferenceStep("child") if present, then delegate.
    # Skip canonical TypeReferenceStep checkpoints before reading the `child` step.
    reference = reference
    if reference isa ConcreteReference
        h = get_reference_head(reference)
        if h isa FieldReferenceStep && h.name == "child"
            return map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, get_reference_tail(reference))
        end
        # References into TooltipSource's other fields (content, style, id)
        # have no image in the output.
        return nothing
    end
    return reference
end

function map_reference_backward(::TooltipDecoratorProjection, iomap::TooltipDecoratorIoMap, reference)
    inner = map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)
    inner === nothing && return nothing
    ConcreteReference(FieldReferenceStep("child"), inner)
end
