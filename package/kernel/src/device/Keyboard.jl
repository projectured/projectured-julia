"""
    KeyboardModule

Backend-agnostic keyboard types. Three event structs model the full
keyboard lifecycle:

- `KeyDown`  — a physical key was pressed (from `SDL_KEYDOWN`). Carries
               the key symbol, all modifier flags, and a `repeat` flag
               for auto-repeated events while the key is held. Used for
               navigation, shortcuts, and non-character actions.
- `KeyUp`    — a physical key was released (from `SDL_KEYUP`). Same
               key/modifier fields as `KeyDown`.
- `KeyPress` — a logical character was produced by the OS input method
               (from `SDL_TEXTINPUT`). Carries the decoded Unicode `Char`
               and the raw UTF-8 `text` string. Used for character insertion.

The first three carry a `Modifiers` struct for Ctrl/Shift/Alt/Meta state.

- `KeyChord` — a *synthesised* multi-key gesture: a recognised **sequence** of
               `KeyDown`s (e.g. `Ctrl-C Ctrl-K`) collapsed into one event by the
               editor's `GestureRecognizer`. Like `MousePress`, it is not
               produced by the backend; it is a combination of raw key events.
"""
module KeyboardModule

import ..DeviceModule: Device
import ..ModifiersModule: Modifiers

export Keyboard, KeyDown, KeyUp, KeyPress, KeyChord
export is_ctrl, is_shift, is_alt, is_meta

"""
    Keyboard()

A keyboard input device. Included among the `devices` passed to
`read_from_devices(backend, devices)` to poll for keyboard events.
"""
struct Keyboard <: Device end

# ── KeyDown ────────────────────────────────────────────────────────────

"""
    KeyDown(key::Symbol, modifiers::Modifiers[, repeat::Bool])

Physical key-press event (fired on `SDL_KEYDOWN`).

`key` is one of:
- **Navigation:** `:left`, `:right`, `:up`, `:down`, `:home`, `:end`,
  `:page_up`, `:page_down`
- **Editing:** `:backspace`, `:delete`, `:return`, `:tab`, `:insert`
- **Function:** `:f1`…`:f12`
- **Misc:** `:escape`, `:space`, `:period`, `:caps_lock`, `:zero` (the `0`
  key — used by the Ctrl+0 transform-pane reset)
- **Modifier-only:** `:lctrl`, `:rctrl`, `:lshift`, `:rshift`,
  `:lalt`, `:ralt`, `:lmeta`, `:rmeta`
- **Printable fallback:** `:char` (physical key identity not important;
  the character itself arrives via `KeyPress`)

`repeat` is `true` when SDL is generating auto-repeat events while the
key is held.
"""
struct KeyDown
    key::Symbol
    modifiers::Modifiers
    repeat::Bool
end

# Convenience: KeyDown without repeat flag (defaults to false).
KeyDown(key::Symbol, modifiers::Modifiers) = KeyDown(key, modifiers, false)

# ── KeyUp ──────────────────────────────────────────────────────────────

"""
    KeyUp(key::Symbol, modifiers::Modifiers)

Physical key-release event (fired on `SDL_KEYUP`). Same `key` vocabulary
as `KeyDown`.
"""
struct KeyUp
    key::Symbol
    modifiers::Modifiers
end

# ── KeyPress ───────────────────────────────────────────────────────────

"""
    KeyPress(char::Char, text::String, modifiers::Modifiers)

Logical character-input event (fired on `SDL_TEXTINPUT`). The OS input
method — including dead-key composition and IME — delivers a fully
composed Unicode character here. Most consumers use the `char` field;
`text` preserves the full UTF-8 string for multi-codepoint inputs.

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

# ── KeyChord ───────────────────────────────────────────────────────────

"""
    KeyChord(keys::Vector{KeyDown})

Synthesised key-chord event: a recognised *sequence* of `KeyDown`s (e.g.
`Ctrl-C` then `Ctrl-K`) collapsed into a single gesture by the editor's
`GestureRecognizer`. `keys` holds the constituent presses in order.

A chord is purely a **combination of events** — it carries no intent. Which
sequences are recognised is configured on the recogniser (its chord table,
empty by default); what a particular chord *means* is each projection reader's
decision, exactly as for any other gesture. The modifiers of each step live on
the individual `KeyDown`s in `keys`.
"""
struct KeyChord
    keys::Vector{KeyDown}
end

# ── Modifier convenience accessors ────────────────────────────────────

"""
    is_ctrl(e)  -> Bool
    is_shift(e) -> Bool
    is_alt(e)   -> Bool
    is_meta(e)  -> Bool

Convenience predicates for the most common modifier checks. Work on
`KeyDown`, `KeyUp`, and `KeyPress`.
"""
is_ctrl(e::Union{KeyDown,KeyUp,KeyPress})  = e.modifiers.ctrl
is_shift(e::Union{KeyDown,KeyUp,KeyPress}) = e.modifiers.shift
is_alt(e::Union{KeyDown,KeyUp,KeyPress})   = e.modifiers.alt
is_meta(e::Union{KeyDown,KeyUp,KeyPress})  = e.modifiers.meta

end # module
