# Fragment of `DeviceModule` — the mouse device.

"""
    Mouse(; button_count=3, has_scroll_wheel=true)

A mouse input device. It carries the physical properties of the pointer — how
many `button_count` buttons it has and whether it `has_scroll_wheel`. The
defaults describe an ordinary 3-button wheel mouse.
"""
mutable struct Mouse <: Device
    button_count::Int
    has_scroll_wheel::Bool
end

Mouse(; button_count::Int=3, has_scroll_wheel::Bool=true) =
    Mouse(button_count, has_scroll_wheel)
