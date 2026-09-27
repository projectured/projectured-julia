# Fragment of `GestureTrackingModule` — the projection that runs the recognitions of
# the gestures over the inputs of the devices.

"""
    GestureTrackingProjection(; inner, recognitions = make_standard_recognitions())

Show the content of a [`GestureTrackingState`](@ref) through `inner`, and give
the content each input and the gestures that the `recognitions` find in the
inputs.

The recognitions run in the order of the list. Each reads the input, and the
inputs that a recognition gives are inputs of the recognitions after it, so a
later recognition can read the gesture of an earlier one, or hold it. A
recognition that holds an input keeps it from the recognitions after it and from
the content. The state of each recognition is a field of the state document, and
a view state operation writes it only when it changes, so an input that changes
no state leaves the answer of the content as it is.

**The order of the content.** The content reads the input in the same read,
unless a recognition holds it; then it reads the first input that the
recognitions give instead. The other inputs wait in the state, and a timer at the
time of the input brings them in, one in each read, after the operation of the
input. A deadline of a recognition becomes a timer of the editor, whose
`TimerExpire` goes to that recognition alone.
"""
struct GestureTrackingProjection <: Projection
    inner::Projection
    recognitions::Vector{GestureRecognition}
end

GestureTrackingProjection(; inner::Projection, recognitions::Vector = make_standard_recognitions()) =
    GestureTrackingProjection(inner, GestureRecognition[r for r in recognitions])

# The timer that brings in a waiting input, and the prefix of the timer of each
# recognition, which ends with its place in the list.
const _WAITING_TIMER = :gesture_tracking_waiting
const _RECOGNITION_TIMER_PREFIX = "gesture_tracking_"

_get_recognition_timer(index::Int) = Symbol(_RECOGNITION_TIMER_PREFIX, index)

# The place in the list of the recognition that the timer `name` belongs to, or
# `nothing` for a timer of no recognition of `p`.
function _find_recognition_index(p::GestureTrackingProjection, name::Symbol)
    text = String(name)
    startswith(text, _RECOGNITION_TIMER_PREFIX) || return nothing
    index = tryparse(Int, text[(length(_RECOGNITION_TIMER_PREFIX) + 1):end])
    index !== nothing && 1 <= index <= length(p.recognitions) ? index : nothing
end

# `output` forwards the output of the content reactively, so the IoMap keeps its
# identity while the content re-derives, and a swap of the content rebuilds the
# child.
@iomap struct GestureTrackingIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

get_child_iomaps(iomap::GestureTrackingIoMap) = Any[iomap.child_iomap]

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::GestureTrackingProjection, recursion, input::GestureTrackingState,
                        ctx)
    child = reconcile_child_iomap(() -> input.content,
                                  content -> print_document(p.inner, recursion, content, ctx))
    GestureTrackingIoMap(p, input, Cell(@computation child[].output), child)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::GestureTrackingProjection, recursion, change::Intent,
                     iomap::GestureTrackingIoMap)
    change.route === nothing || return read_routed_child(recursion, change, iomap)
    input = change.gesture
    if input isa TimerExpire
        input.name === _WAITING_TIMER && return Intent(input, _read_waiting(p, recursion, iomap, input))
        index = _find_recognition_index(p, input.name)
        index === nothing ||
            return Intent(input, _read_recognized(p, recursion, change, iomap, index, input,
                                                  nothing; own_timer = true))
    elseif input isa WindowInput
        return Intent(input, _read_recognized(p, recursion, change, iomap, 1, input.event,
                                              input.window_id))
    end
    Intent(input, _read_content(p, recursion, change, iomap))
end

read_intent(p::GestureTrackingProjection, iomap::GestureTrackingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# The answer of the content to `change`, as an operation from the state.
function _read_content(p::GestureTrackingProjection, recursion, change::Intent,
                       iomap::GestureTrackingIoMap)
    answer = read_intent(p.inner, recursion, change, iomap.child_iomap)
    operation = answer isa Intent ? answer.operation : answer
    reroot_operation(operation, (FieldReferenceStep("content"),))
end

# A write of one field of the state, which a history does not record.
_write_state(state::GestureTrackingState, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(state, field, value))

# The operations in order, without the ones that are `nothing`, as one operation.
function _join_operations(operations...)
    kept = Any[operation for operation in operations if operation !== nothing]
    isempty(kept) ? nothing : length(kept) == 1 ? kept[1] : CompoundOperation(kept)
end

# The state of the recognition at `index`: its entry, or its first state.
_get_recognition_state(p::GestureTrackingProjection, states, index::Int) =
    index <= length(states) ? states[index] : make_recognition_state(p.recognitions[index])

# Run the recognitions from `from` on over `input`. Updates `states` and collects
# the timers; answers whether a recognition held the input, and the inputs that
# the recognitions give for the content, in order.
function _run_recognitions!(p::GestureTrackingProjection, states::Vector{Any}, timers::Vector{Any},
                            from::Int, input, window)
    given = Tuple{Int,WindowInput}[]
    held = false
    for index in from:length(p.recognitions)
        step = recognize(p.recognitions[index], states[index], input, window)
        states[index] = step.state
        step.deadline === nothing ||
            push!(timers, SetTimerOperation(_get_recognition_timer(index), step.deadline))
        append!(given, [(index, output) for output in step.inputs])
        step.held && (held = true; break)
    end
    delivered = WindowInput[]
    for (index, output) in given
        later_held, later = _run_recognitions!(p, states, timers, index + 1, output.event,
                                               output.window_id)
        later_held || push!(delivered, output)
        append!(delivered, later)
    end
    (held, delivered)
end

# One input through the recognitions from `from` on, and the content: the input,
# or the first input that the recognitions give when one holds it; the others
# wait. A timer of a recognition is its own, so the content never reads it.
function _read_recognized(p::GestureTrackingProjection, recursion, change::Intent,
                          iomap::GestureTrackingIoMap, from::Int, input, window;
                          own_timer::Bool = false)
    state = iomap.input
    before = Any[_get_recognition_state(p, state.states, index)
                 for index in eachindex(p.recognitions)]
    states = copy(before)
    timers = Any[]
    held, delivered = _run_recognitions!(p, states, timers, from, input, window)
    content = if !(held || own_timer)
        _read_content(p, recursion, change, iomap)
    elseif !isempty(delivered)
        _read_content(p, recursion, Intent(popfirst!(delivered), nothing), iomap)
    end
    states_write = isequal(Tuple(states), Tuple(before)) ? nothing :
                   _write_state(state, "states", Tuple(states))
    waiting = isempty(delivered) ? () :
              (_write_state(state, "waiting", (state.waiting..., delivered...)),
               SetTimerOperation(_WAITING_TIMER, get_event_time(input)))
    _join_operations(content, states_write, waiting..., timers...)
end

# The next input that waits for the content.
function _read_waiting(p::GestureTrackingProjection, recursion, iomap::GestureTrackingIoMap,
                       timer::TimerExpire)
    state = iomap.input
    isempty(state.waiting) && return nothing
    next, rest = first(state.waiting), Base.tail(state.waiting)
    _join_operations(_read_content(p, recursion, Intent(next, nothing), iomap),
                     _write_state(state, "waiting", rest),
                     isempty(rest) ? nothing : SetTimerOperation(_WAITING_TIMER, timer.time))
end

# ── Reference mapping (transparent, through the `content` field) ───────────

function map_reference_forward(p::GestureTrackingProjection, iomap::GestureTrackingIoMap,
                               reference)
    reference isa ConcreteReference || return reference
    head = get_reference_head(reference)
    head isa FieldReferenceStep && head.name == "content" || return nothing
    map_reference_forward(p.inner, iomap.child_iomap, get_reference_tail(reference))
end

function map_reference_backward(p::GestureTrackingProjection, iomap::GestureTrackingIoMap,
                                reference)
    inner = map_reference_backward(p.inner, iomap.child_iomap, reference)
    inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("content"), inner)
end
