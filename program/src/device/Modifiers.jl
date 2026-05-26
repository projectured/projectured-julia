"""
    ModifiersModule

Shared modifier-key state used by both keyboard and mouse events.
"""
module ModifiersModule

export Modifiers

"""
    Modifiers(ctrl, shift, alt, meta)

Immutable struct carrying the state of the four common modifier keys.
- `ctrl`  — either Ctrl key (KMOD_LCTRL | KMOD_RCTRL)
- `shift` — either Shift key (KMOD_LSHIFT | KMOD_RSHIFT)
- `alt`   — either Alt/Option key (KMOD_LALT | KMOD_RALT)
- `meta`  — Super/Windows/Command key (KMOD_LGUI | KMOD_RGUI)

Convenience constructors:
- `Modifiers()` — all false (no modifier held)
- `Modifiers(ctrl=true)` — keyword form; unspecified fields default to false
"""
struct Modifiers
    ctrl::Bool
    shift::Bool
    alt::Bool
    meta::Bool
end

# Keyword constructor — any subset of fields, all defaulting to false.
Modifiers(; ctrl::Bool=false, shift::Bool=false, alt::Bool=false, meta::Bool=false) =
    Modifiers(ctrl, shift, alt, meta)

end # module
