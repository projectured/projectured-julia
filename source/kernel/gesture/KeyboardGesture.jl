# Fragment of `GestureModule` — the gesture of the keyboard: `KeyChord`, a sequence of
# `KeyDown`s that a chord table names.

"""
    KeyChord(keys::Vector{KeyDown}; time)
    KeyChord(keys, time)

A sequence of `KeyDown`s as one gesture, such as Ctrl+C and then Ctrl+K. `keys`
holds the `KeyDown`s in order, and each holds its own modifiers. `time` is the time
of the last key.

A chord is only a combination of events, and it carries no intent. Other code
states which sequences are chords, and the code that reads a chord gives it its
meaning, as for any other gesture.
"""
struct KeyChord <: Gesture
    keys::Vector{KeyDown}
    time::Float64
end

KeyChord(keys::Vector{KeyDown}; time::Real) = KeyChord(keys, Float64(time))
