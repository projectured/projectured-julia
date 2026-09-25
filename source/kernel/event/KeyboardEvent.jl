# Fragment of `EventModule` — the keyboard events. An event source reports
# `KeyDown`, `KeyUp` and `KeyPress`, and `KeyChord` comes from a sequence of
# `KeyDown`s.

"""
    KeyDown(key::Symbol, modifiers::ModifierKeys[, repeat::Bool])

A key went down.

`key` names the key. The names include:
- the keys that move: `:left`, `:right`, `:up`, `:down`, `:home`, `:end`,
  `:page_up` and `:page_down`;
- the keys that edit: `:backspace`, `:delete`, `:return`, `:tab` and `:insert`;
- the function keys, `:f1` to `:f12`;
- other keys: `:escape`, `:space` and `:caps_lock`;
- letters, such as `:c`, and punctuation: `:period`, `:minus`, `:slash`,
  `:backslash`, `:asterisk`, `:equals` and `:zero`, the `0` key;
- the modifier keys: `:lctrl`, `:rctrl`, `:lshift`, `:rshift`, `:lalt`, `:ralt`,
  `:lmeta` and `:rmeta`;
- `:char`, for a key whose name does not matter, because its character comes in a
  `KeyPress`.

`repeat` is `true` for an event that the operating system repeats while the key is
held. Without `repeat`, the event is not a repeat.
"""
struct KeyDown <: DeviceEvent
    key::Symbol
    modifiers::ModifierKeys
    repeat::Bool
end

KeyDown(key::Symbol, modifiers::ModifierKeys) = KeyDown(key, modifiers, false)

"""
    KeyUp(key::Symbol, modifiers::ModifierKeys)

A key went up. `key` names the key as for `KeyDown`.
"""
struct KeyUp <: DeviceEvent
    key::Symbol
    modifiers::ModifierKeys
end

"""
    KeyPress(char::Char, text::String, modifiers::ModifierKeys)

A character was typed. The input method of the operating system gives the
composed Unicode character, after a dead key or an input method for another script.
`char` holds the character, and `text` holds the full string, for an input of more
than one code point.

`KeyPress(char)` has no modifiers, and `KeyPress(char, modifiers)` takes them. Both
set `text` to the character.
"""
struct KeyPress <: DeviceEvent
    char::Char
    text::String
    modifiers::ModifierKeys
end

KeyPress(char::Char) = KeyPress(char, string(char), ModifierKeys())
KeyPress(char::Char, mods::ModifierKeys) = KeyPress(char, string(char), mods)

"""
    KeyChord(keys::Vector{KeyDown})

A sequence of `KeyDown`s as one event, such as Ctrl+C and then Ctrl+K. `keys` holds
the `KeyDown`s in order, and each holds its own modifiers.

A chord is only a combination of events, and it carries no intent. Other code
states which sequences are chords, and the code that reads a chord gives it its
meaning, as for any other event.
"""
struct KeyChord <: SyntheticEvent
    keys::Vector{KeyDown}
end

get_modifier_keys(event::Union{KeyDown,KeyUp,KeyPress}) = event.modifiers
