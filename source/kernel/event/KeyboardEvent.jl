# Fragment of `EventModule` — the keyboard events. An event source reports the
# events `KeyDown`, `KeyUp` and `KeyPress`.

"""
    KeyDown(key::Symbol, modifiers::ModifierKeys; repeat = false, time)
    KeyDown(key, modifiers, repeat, time)

A key went down.

`key` names the key. The names include:
- the keys that move: `:left`, `:right`, `:up`, `:down`, `:home`, `:end`,
  `:page_up` and `:page_down`;
- the keys that edit: `:backspace`, `:delete`, `:return`, `:tab` and `:insert`;
- the function keys, `:f1` to `:f12`;
- other keys: `:escape`, `:space` and `:caps_lock`;
- the letter keys: each has the name of its lower-case letter, `:a` to `:z`, in
  every backend;
- punctuation: `:period`, `:comma`, `:minus`, `:slash`, `:backslash`, `:asterisk`,
  `:equals`, `:zero`, the `0` key, and `:left_bracket`/`:right_bracket`, `[` and
  `]`;
- the modifier keys: `:lctrl`, `:rctrl`, `:lshift`, `:rshift`, `:lalt`, `:ralt`,
  `:lmeta` and `:rmeta`;
- `:char`, for a key whose name does not matter, because its character comes in a
  `KeyPress`.

`repeat` is `true` for an event that the operating system repeats while the key is
held. The short form takes `repeat` as a keyword, and its default is `false`. `time`
is the time of the input (see `Event`).
"""
struct KeyDown <: Event
    key::Symbol
    modifiers::ModifierKeys
    repeat::Bool
    time::Float64
end

KeyDown(key::Symbol, modifiers::ModifierKeys; repeat::Bool = false, time::Real) =
    KeyDown(key, modifiers, repeat, Float64(time))

"""
    KeyUp(key::Symbol, modifiers::ModifierKeys; time)
    KeyUp(key, modifiers, time)

A key went up. `key` names the key as for `KeyDown`.
"""
struct KeyUp <: Event
    key::Symbol
    modifiers::ModifierKeys
    time::Float64
end

KeyUp(key::Symbol, modifiers::ModifierKeys; time::Real) =
    KeyUp(key, modifiers, Float64(time))

"""
    KeyPress(char::Char, text::String, modifiers::ModifierKeys; time)
    KeyPress(char, text, modifiers, time)

A character was typed. The input method of the operating system gives the
composed Unicode character, after a dead key or an input method for another script.
`char` holds the character, and `text` holds the full string, for an input of more
than one code point.

`KeyPress(char; time)` has no modifiers, and `KeyPress(char, modifiers; time)`
takes them. Both set `text` to the character.
"""
struct KeyPress <: Event
    char::Char
    text::String
    modifiers::ModifierKeys
    time::Float64
end

KeyPress(char::Char, text::String, modifiers::ModifierKeys; time::Real) =
    KeyPress(char, text, modifiers, Float64(time))
KeyPress(char::Char; time::Real) =
    KeyPress(char, string(char), ModifierKeys(), Float64(time))
KeyPress(char::Char, modifiers::ModifierKeys; time::Real) =
    KeyPress(char, string(char), modifiers, Float64(time))

get_modifier_keys(event::Union{KeyDown,KeyUp,KeyPress}) = event.modifiers
