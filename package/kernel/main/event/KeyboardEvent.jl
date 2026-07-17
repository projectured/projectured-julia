# Fragment of `EventModule` — the keyboard events.
#
# Three of them model the physical/logical keyboard lifecycle a backend reports;
# `KeyChord` is synthesised from a recognised *sequence* of `KeyDown`s.

"""
    KeyDown(key::Symbol, modifiers::ModifierKeys[, repeat::Bool])

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
struct KeyDown <: DeviceEvent
    key::Symbol
    modifiers::ModifierKeys
    repeat::Bool
end

# Convenience: KeyDown without repeat flag (defaults to false).
KeyDown(key::Symbol, modifiers::ModifierKeys) = KeyDown(key, modifiers, false)

"""
    KeyUp(key::Symbol, modifiers::ModifierKeys)

Physical key-release event. Same `key` vocabulary as `KeyDown`.
"""
struct KeyUp <: DeviceEvent
    key::Symbol
    modifiers::ModifierKeys
end

"""
    KeyPress(char::Char, text::String, modifiers::ModifierKeys)

Logical character-input event. The OS input method — including dead-key
composition and IME — delivers a fully composed Unicode character here. Most
consumers use the `char` field; `text` preserves the full UTF-8 string for
multi-codepoint inputs.

Convenience constructors:
- `KeyPress(char)` — wraps a single character, no modifiers
- `KeyPress(char, mods)` — wraps a character with modifiers
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

Synthesised key-chord event: a recognised *sequence* of `KeyDown`s (e.g. `Ctrl-C`
then `Ctrl-K`) collapsed into a single event. `keys` holds the constituent
presses in order, and the modifiers of each step live on those `KeyDown`s.

A chord is purely a **combination of events** — it carries no intent. Which
sequences are recognised is a recogniser's configuration; what a particular chord
*means* is the decision of whoever reads it, exactly as for any other event.
"""
struct KeyChord <: SyntheticEvent
    keys::Vector{KeyDown}
end

get_modifiers(event::Union{KeyDown,KeyUp,KeyPress}) = event.modifiers
