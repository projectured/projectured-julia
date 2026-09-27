# Fragment of `MouseTargetTrackingModule` — the projection that keeps the part
# under the pointer and gives the crossings to its parts.

"""
    MouseTargetTrackingProjection(; inner)

Show the content of a [`MouseTargetTrackingState`](@ref) through `inner`, and
keep the part under the pointer, the target.

**The target.** On a `MouseMove`, the projection maps the point backward through
`inner`: the point in window `w` of a content with `windows` is the point step
after `windows[i].content`, and a content with no windows takes the bare point.
A point step at the end of the answer is no part of the target, so a plot is the
same target at every point of it. The parts of the target are the prefixes of
its path that name a document, the outer first.

**The crossings.** When the target changes, each part of the old target that is
not on the new one gets a `MouseLeave`, the inner first, and each part of the
new target that is not on the old one gets a `MouseEnter`, the outer first. When
the target stays, its deepest part gets a `MouseHover`, at the point step of the
answer when there is one, and at the point in the window otherwise. A
`DisplayUpdate` of the window of the pointer finds the target again at the last
position, because the view can change under a still pointer. A `WindowLeave` of
that window gives every part a leave and clears the target.

**The delivery.** Each crossing goes to its part by route. The content reads the
input first; the crossings wait in the state, and a timer at the time of the
input brings them in, one in each read, after the operation of the input.
"""
struct MouseTargetTrackingProjection <: Projection
    inner::Projection
end

MouseTargetTrackingProjection(; inner::Projection) = MouseTargetTrackingProjection(inner)

# The timer that brings in a crossing that waits.
const _WAITING_TIMER = :mouse_target_tracking_waiting

# `output` forwards the output of the content reactively, so the IoMap keeps its
# identity while the content re-derives, and a swap of the content rebuilds the
# child.
@iomap struct MouseTargetTrackingIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

get_child_iomaps(iomap::MouseTargetTrackingIoMap) = Any[iomap.child_iomap]

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::MouseTargetTrackingProjection, recursion,
                        input::MouseTargetTrackingState, ctx)
    child = reconcile_child_iomap(() -> input.content,
                                  content -> print_document(p.inner, recursion, content, ctx))
    MouseTargetTrackingIoMap(p, input, Cell(@computation child[].output), child)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::MouseTargetTrackingProjection, recursion, change::Intent,
                     iomap::MouseTargetTrackingIoMap)
    change.route === nothing || return read_routed_child(recursion, change, iomap)
    input = change.gesture
    input isa TimerExpire && input.name === _WAITING_TIMER &&
        return Intent(input, _read_waiting(p, recursion, iomap, input))
    content = _read_content(p, recursion, change, iomap)
    input isa WindowInput || return Intent(input, content)
    event = input.event
    state = iomap.input
    own = if event isa MouseMove
        position = _Position(input.window_id, event.x, event.y, event.buttons, event.modifiers)
        _track(p, iomap, position, event.time; hover = true)
    elseif event isa DisplayUpdate && _is_pointer_window(state.position, input.window_id)
        _track(p, iomap, state.position, event.time; hover = false)
    elseif event isa WindowLeave && _is_pointer_window(state.position, input.window_id)
        _leave_target(state, event.time)
    else
        ()
    end
    Intent(input, _join_operations(content, own...))
end

read_intent(p::MouseTargetTrackingProjection, iomap::MouseTargetTrackingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

_is_pointer_window(position, window) = position !== nothing && position.window === window

# The answer of the content to `change`, as an operation from the state.
function _read_content(p::MouseTargetTrackingProjection, recursion, change::Intent,
                       iomap::MouseTargetTrackingIoMap)
    answer = read_intent(p.inner, recursion, change, iomap.child_iomap)
    operation = answer isa Intent ? answer.operation : answer
    reroot_operation(operation, (FieldReferenceStep("content"),))
end

# A write of one field of the state, which a history does not record.
_write_state(state::MouseTargetTrackingState, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(state, field, value))

# The operations in order, without the ones that are `nothing`, as one operation.
function _join_operations(operations...)
    kept = Any[operation for operation in operations if operation !== nothing]
    isempty(kept) ? nothing : length(kept) == 1 ? kept[1] : CompoundOperation(kept)
end

# The crossings wait for the content, and a timer at `time` brings them in.
_wait_for_content(state::MouseTargetTrackingState, crossings, time::Float64) =
    isempty(crossings) ? () :
    (_write_state(state, "waiting", (state.waiting..., crossings...)),
     SetTimerOperation(_WAITING_TIMER, time))

# ── The target ────────────────────────────────────────────────────────────

# The steps from the content to the view of `window`: `windows[i].content` for a
# content with windows, none for a content that is the view itself, and
# `nothing` for a window that the content does not have.
function _find_window_steps(content, window)
    hasproperty(content, :windows) || return ()
    for (index, candidate) in enumerate(content.windows)
        candidate.id === window && return (FieldReferenceStep("windows"),
                                           ElementReferenceStep(index),
                                           FieldReferenceStep("content"))
    end
    nothing
end

# The target at `position`, without a point step at its end, and that point step,
# or `(nothing, nothing)` when no part is there.
function _find_target(p::MouseTargetTrackingProjection, iomap::MouseTargetTrackingIoMap,
                      position::_Position)
    steps = _find_window_steps(iomap.input.content, position.window)
    steps === nothing && return (nothing, nothing)
    point = extend_reference(EmptyReference(), steps..., PointReferenceStep(position.x, position.y))
    answer = map_reference_backward(p.inner, iomap.child_iomap, point)
    answer === nothing && return (nothing, nothing)
    found = collect(get_reference_steps(strip_reference_types(answer)))
    local_point = !isempty(found) && last(found) isa PointReferenceStep ? last(found) : nothing
    while !isempty(found) && last(found) isa PointReferenceStep
        pop!(found)
    end
    (extend_reference(EmptyReference(), found...), local_point)
end

# The prefixes of `target` that name a document of `content`, the outer first.
# The content itself is no part: every target is on it.
function _find_parts(content, target)
    target === nothing && return ()
    steps = collect(get_reference_steps(target))
    parts = Reference[]
    for length_ in 1:length(steps)
        prefix = extend_reference(EmptyReference(), steps[1:length_]...)
        try_evaluate_reference(content, prefix, nothing) isa Document && push!(parts, prefix)
    end
    Tuple(parts)
end

# The writes of the target at `position`, and its crossings. `hover` says whether
# a target that stays gets a `MouseHover`: a motion does, a new frame does not.
function _track(p::MouseTargetTrackingProjection, iomap::MouseTargetTrackingIoMap,
                position::_Position, time::Float64; hover::Bool)
    state = iomap.input
    target, local_point = _find_target(p, iomap, position)
    parts = _find_parts(state.content, target)
    old = state.parts
    x, y, b, m = position.x, position.y, position.buttons, position.modifiers
    crossings = _Crossing[]
    for part in Iterators.reverse(old)
        part in parts || push!(crossings, _Crossing(part, MouseLeave(x, y, b, m; time)))
    end
    for part in parts
        part in old || push!(crossings, _Crossing(part, MouseEnter(x, y, b, m; time)))
    end
    if hover && isempty(crossings) && !isempty(parts)
        hx, hy = local_point === nothing ? (x, y) : (local_point.x, local_point.y)
        push!(crossings, _Crossing(last(parts), MouseHover(hx, hy, b, m; time)))
    end
    writes = Any[]
    isequal(target, state.target) || push!(writes, _write_state(state, "target", target))
    isequal(parts, old) || push!(writes, _write_state(state, "parts", parts))
    isequal(position, state.position) || push!(writes, _write_state(state, "position", position))
    (writes..., _wait_for_content(state, crossings, time)...)
end

# The pointer left the window: a leave to every part, the inner first, and no
# target.
function _leave_target(state::MouseTargetTrackingState, time::Float64)
    position = state.position
    x, y, b, m = position.x, position.y, position.buttons, position.modifiers
    crossings = [_Crossing(part, MouseLeave(x, y, b, m; time)) for part in Iterators.reverse(state.parts)]
    (_write_state(state, "target", nothing), _write_state(state, "parts", ()),
     _write_state(state, "position", nothing), _wait_for_content(state, crossings, time)...)
end

# The next crossing that waits, to its part by route.
function _read_waiting(p::MouseTargetTrackingProjection, recursion,
                       iomap::MouseTargetTrackingIoMap, timer::TimerExpire)
    state = iomap.input
    isempty(state.waiting) && return nothing
    next, rest = first(state.waiting), Base.tail(state.waiting)
    routed = Intent(next.gesture, nothing, "", "", next.route)
    _join_operations(_read_content(p, recursion, routed, iomap),
                     _write_state(state, "waiting", rest),
                     isempty(rest) ? nothing : SetTimerOperation(_WAITING_TIMER, timer.time))
end

# ── Reference mapping (transparent, through the `content` field) ───────────

function map_reference_forward(p::MouseTargetTrackingProjection, iomap::MouseTargetTrackingIoMap,
                               reference)
    reference isa ConcreteReference || return reference
    head = get_reference_head(reference)
    head isa FieldReferenceStep && head.name == "content" || return nothing
    map_reference_forward(p.inner, iomap.child_iomap, get_reference_tail(reference))
end

function map_reference_backward(p::MouseTargetTrackingProjection, iomap::MouseTargetTrackingIoMap,
                                reference)
    inner = map_reference_backward(p.inner, iomap.child_iomap, reference)
    inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("content"), inner)
end
