# Fragment of `DeviceModule` — the keyboard device.

"""
    Keyboard(; layout=:qwerty)

A keyboard input device. It carries the physical `layout` of the keys
(`:qwerty`, `:azerty`, `:dvorak`, …); the default is `:qwerty`.
"""
mutable struct Keyboard <: Device
    layout::Symbol
end

Keyboard(; layout::Symbol=:qwerty) = Keyboard(layout)
