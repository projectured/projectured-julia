# Fragment of `GestureModule` — the recognition of a gesture: a pure rule that
# reads one input and its own state, and answers the next state and what it found.

"""
    GestureRecognition

The supertype of the recognition of one kind of gesture. A recognition is a pure
rule: it reads one input and its own state, and it answers a
[`RecognitionStep`](@ref). It holds its settings, such as the time of a click,
and no state: the state is a value that the code which runs the recognition
keeps, for example the state document of a tracking projection.

A package adds a gesture with a gesture type, a recognition and two methods:
[`make_recognition_state`](@ref) and [`recognize`](@ref). A host adds the
recognition to the list that it runs, and the readers match the new gesture
with `@gesture_case`.
"""
abstract type GestureRecognition end

"""
    make_recognition_state(recognition) -> state

The state of `recognition` before any input: an immutable value, which each
step replaces.
"""
function make_recognition_state end

"""
    recognize(recognition, state, input, window) -> RecognitionStep

Read `input`, an event or a gesture, with `state`, and answer the next state and
what the input gives. `window` is the id of the window that the input came
from, or `nothing` for an input of no window, such as a `TimerExpire`.

A time comes as an input too: a step that answers a deadline gets a
`TimerExpire` with that time, unless a later step of the same recognition
answers a newer deadline first. The times are the times of the inputs, so a
replay gives the same gestures.
"""
function recognize end

"""
    RecognitionStep(state; inputs = WindowInput[], deadline = nothing, held = false)

What one input gives a recognition:

- `state` — the next state.
- `inputs` — the inputs that follow the one it read, in order: the gestures
  that the input completes, or inputs that the recognition kept and now gives
  back, each with its window.
- `deadline` — a time at which the recognition wants to read again, or
  `nothing`.
- `held` — whether the recognition keeps the input from the recognitions after
  it and from the reader, as a key of a chord in progress.
"""
struct RecognitionStep
    state::Any
    inputs::Vector{WindowInput}
    deadline::Union{Float64,Nothing}
    held::Bool
end

RecognitionStep(state; inputs::Vector = WindowInput[], deadline = nothing,
                held::Bool = false) =
    RecognitionStep(state, WindowInput[input for input in inputs],
                    deadline === nothing ? nothing : Float64(deadline), held)

# A limit of a recognition: a number, or a cell that the recognition reads at each
# input, so a setting of the person changes the limit while the editor runs.
_get_limit(limit::Real) = limit
_get_limit(limit::AbstractCell) = limit[]

"""
    make_standard_recognitions() -> Vector{GestureRecognition}

The recognitions that a host runs by default, in their order: the chord, so that
a key that it keeps reaches no later recognition; the click; and the dwell,
which a down and a click stop.
"""
make_standard_recognitions() =
    GestureRecognition[ChordRecognition(), ClickRecognition(), DwellRecognition()]
