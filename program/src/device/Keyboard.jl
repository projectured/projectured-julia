"""
    KeyboardModule

Backend-agnostic keyboard types. The `KeyPress` struct provides a stable
vocabulary of named key symbols so projection readers remain independent
of any particular backend.
"""
module KeyboardModule

import ..DeviceModule: Device
import ..ModifiersModule: Modifiers

export Keyboard, KeyPress

"""
    Keyboard()

A keyboard input device. Passed to `read_from_device(backend, keyboard)`
to poll for keyboard events.
"""
struct Keyboard <: Device end

"""
    KeyPress(key::Symbol, modifiers::Modifiers)

Backend-agnostic keyboard event. `key` is one of:
`:left`, `:right`, `:up`, `:down`, `:home`, `:end`, `:escape`, `:return`, `:char`, `:comma`, `:period`.
`modifiers` carries the Ctrl/Shift/Alt state at the time of the keypress.

For backward compatibility, `KeyPress(key, ctrl::Bool)` constructs a
`KeyPress` with only Ctrl set (Shift and Alt default to `false`).
"""
struct KeyPress
    key::Symbol
    modifiers::Modifiers
end

# Backward-compatible constructor: KeyPress(key, ctrl::Bool)
KeyPress(key::Symbol, ctrl::Bool) = KeyPress(key, Modifiers(ctrl, false, false))

end # module
