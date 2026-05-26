"""
    KeyboardModule

Backend-agnostic keyboard types. The `KeyPress` struct provides a stable
vocabulary of named key symbols so projection readers remain independent
of any particular backend.
"""
module KeyboardModule

import ..DeviceModule: Device

export Keyboard, KeyPress

"""
    Keyboard()

A keyboard input device. Passed to `read_from_device(backend, keyboard)`
to poll for keyboard events.
"""
struct Keyboard <: Device end

"""
    KeyPress(key::Symbol, ctrl::Bool)

Backend-agnostic keyboard event. `key` is one of:
`:left`, `:right`, `:up`, `:down`, `:home`, `:end`, `:escape`, `:return`, `:char`, `:comma`, `:period`.
`ctrl` is true when any Ctrl modifier was held.
"""
struct KeyPress
    key::Symbol
    ctrl::Bool
end

end # module
