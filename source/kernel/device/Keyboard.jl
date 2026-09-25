# Fragment of `DeviceModule` — the keyboard device.

"""
    Keyboard(; layout = :qwerty)

A keyboard. `layout` names the arrangement of its keys, for example `:qwerty`,
`:azerty` or `:dvorak`.
"""
mutable struct Keyboard <: Device
    layout::Symbol
end

Keyboard(; layout::Symbol = :qwerty) = Keyboard(layout)
