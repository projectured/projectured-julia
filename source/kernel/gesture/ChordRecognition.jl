# Fragment of `GestureModule` — the recognition of a key chord.

"""
    ChordRecognition(chords = Vector{Vector{KeyDown}}())

A `KeyChord` in place of a sequence of `KeyDown`s of the chord table `chords`.
Each entry of the table is a sequence, whose steps match on the key and the
modifiers, whatever their `repeat` flag.

The recognition holds a key that continues a sequence, and it gives the
`KeyChord` when the key that completes it comes, at the time of that key. A key
that breaks the sequence gives back the kept keys and itself, in order, and it
does not start a new chord. A repeated key neither starts nor continues a chord,
and it is dropped while keys are kept. With an empty table, which is the default,
every key goes on.
"""
struct ChordRecognition <: GestureRecognition
    chords::Vector{Vector{KeyDown}}
end

ChordRecognition() = ChordRecognition(Vector{Vector{KeyDown}}())

# The state is the tuple of the kept keys, each with its window.
make_recognition_state(::ChordRecognition) = ()

recognize(::ChordRecognition, kept::Tuple, input, window) = RecognitionStep(kept)

function recognize(recognition::ChordRecognition, kept::Tuple, event::KeyDown, window)
    isempty(recognition.chords) && return RecognitionStep(kept)
    event.repeat && return RecognitionStep(kept; held = !isempty(kept))
    keys = (kept..., WindowInput(window, event))
    if any(chord -> _is_chord_prefix(keys, chord), recognition.chords)
        any(chord -> length(chord) == length(keys) && _is_chord_prefix(keys, chord),
            recognition.chords) || return RecognitionStep(keys; held = true)
        chord = KeyChord(KeyDown[key.event for key in keys]; time = get_event_time(event))
        return RecognitionStep((); inputs = [WindowInput(first(keys).window_id, chord)],
                               held = true)
    end
    isempty(kept) && return RecognitionStep(kept)
    RecognitionStep((); inputs = collect(keys), held = true)
end

# Whether the keys of `keys` are the first steps of `chord`: the same key and
# modifiers, whatever the `repeat` flag.
function _is_chord_prefix(keys, chord::Vector{KeyDown})
    length(keys) <= length(chord) || return false
    all(i -> chord[i].key == keys[i].event.key &&
             chord[i].modifiers == keys[i].event.modifiers,
        eachindex(keys))
end
