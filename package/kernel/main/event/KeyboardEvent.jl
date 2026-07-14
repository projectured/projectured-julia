# Fragment of `EventModule` — the keyboard events.
#
# Three of them model the physical/logical keyboard lifecycle a backend reports;
# `KeyChord` is synthesised from a recognised *sequence* of `KeyDown`s.

"""
    KeyDown(key::Symbol, modifiers::Modifiers[, repeat::Bool])

Physical key-press event.

`key` is one of:
- **Navigation:** `:left`, `:right`, `:up`, `:down`, `:home`, `:end`,
  `:page_up`, `:page_down`
- **Editing:** `:backspace`, `:delete`, `:return`, `:tab`, `:insert`
- **Function:** `:f1`…`:f12`
- **Misc:** `:escape`, `:space`, `:period`, `:caps_lock`, `:zero` (the `0` key)
- **Modifier-only:** `:lctrl`, `:rctrl`, `:lshift`, `:rshift`,
  `:lalt`, `:ralt`, `:lmeta`, `:rmeta`
- **Printable fallback:** `:char` (physical key identity not important;
  the character itself arrives via `KeyPress`)

`repeat` is `true` for the auto-repeat events generated while the key is held.
"""
struct KeyDown
    key::Symbol
    modifiers::Modifiers
    repeat::Bool
end

# Convenience: KeyDown without repeat flag (defaults to false).
KeyDown(key::Symbol, modifiers::Modifiers) = KeyDown(key, modifiers, false)

"""
    KeyUp(key::Symbol, modifiers::Modifiers)

Physical key-release event. Same `key` vocabulary as `KeyDown`.
"""
struct KeyUp
    key::Symbol
    modifiers::Modifiers
end

"""
    KeyPress(char::Char, text::String, modifiers::Modifiers)

Logical character-input event. The OS input method — including dead-key
composition and IME — delivers a fully composed Unicode character here. Most
consumers use the `char` field; `text` preserves the full UTF-8 string for
multi-codepoint inputs.

Convenience constructors:
- `KeyPress(char)` — wraps a single character, no modifiers
- `KeyPress(char, mods)` — wraps a character with modifiers
"""
struct KeyPress
    char::Char
    text::String
    modifiers::Modifiers
end

KeyPress(char::Char) = KeyPress(char, string(char), Modifiers())
KeyPress(char::Char, mods::Modifiers) = KeyPress(char, string(char), mods)

"""
    KeyChord(keys::Vector{KeyDown})

Synthesised key-chord event: a recognised *sequence* of `KeyDown`s (e.g. `Ctrl-C`
then `Ctrl-K`) collapsed into a single event. `keys` holds the constituent
presses in order, and the modifiers of each step live on those `KeyDown`s.

A chord is purely a **combination of events** — it carries no intent. Which
sequences are recognised is a recogniser's configuration; what a particular chord
*means* is the decision of whoever reads it, exactly as for any other event.
"""
struct KeyChord
    keys::Vector{KeyDown}
end

"""
    is_ctrl(e)  -> Bool
    is_shift(e) -> Bool
    is_alt(e)   -> Bool
    is_meta(e)  -> Bool

Convenience predicates for the most common modifier checks. Work on `KeyDown`,
`KeyUp`, and `KeyPress`.
"""
is_ctrl(e::Union{KeyDown,KeyUp,KeyPress})  = e.modifiers.ctrl
is_shift(e::Union{KeyDown,KeyUp,KeyPress}) = e.modifiers.shift
is_alt(e::Union{KeyDown,KeyUp,KeyPress})   = e.modifiers.alt
is_meta(e::Union{KeyDown,KeyUp,KeyPress})  = e.modifiers.meta
