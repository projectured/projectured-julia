# Fragment of `EventModule` — the modifier-key state shared by keyboard and
# mouse events.

"""
    Modifiers(ctrl, shift, alt, meta)

Immutable struct carrying the state of the four common modifier keys.
- `ctrl`  — either Ctrl key
- `shift` — either Shift key
- `alt`   — either Alt/Option key
- `meta`  — Super/Windows/Command key

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
