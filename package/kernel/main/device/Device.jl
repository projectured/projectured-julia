# Fragment of `DeviceModule` — the device **contract**: the `Device` supertype
# every device subtypes. The concrete devices an editor is given live in the
# sibling `Keyboard.jl` / `Mouse.jl` / `Screen.jl` fragments.

"""
    Device

Abstract supertype for all I/O devices (screen, keyboard, mouse, …).
"""
abstract type Device end
