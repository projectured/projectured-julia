# Fragment of `DeviceModule` — the mouse device.

"""
    Mouse(; button_count = 3, has_scroll_wheel = true)

A mouse. `button_count` is the number of its buttons, and `has_scroll_wheel` is
`true` when it has a scroll wheel. The defaults describe a mouse with three
buttons and a scroll wheel.
"""
mutable struct Mouse <: Device
    button_count::Int
    has_scroll_wheel::Bool
end

Mouse(; button_count::Integer = 3, has_scroll_wheel::Bool = true) =
    Mouse(button_count, has_scroll_wheel)
