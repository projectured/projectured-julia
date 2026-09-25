# Fragment of `EventModule` — the modifier keys that keyboard and mouse events hold.

"""
    ModifierKeys(ctrl, shift, alt, meta)
    ModifierKeys(; ctrl = false, shift = false, alt = false, meta = false)

The modifier keys that are held: one flag for each of `ctrl`, `shift`, `alt` and
`meta`. `ctrl`, `shift` and `alt` are either key of that name, the Option key too for
`alt`, and `meta` is the Super, Windows or Command key.

Use it to state or test the modifier keys of an event.

# Example

    ModifierKeys()                                                          # no modifier
    has_ctrl_modifier_key(KeyDown(:c, ModifierKeys(ctrl = true); time = 0.0))   # true

See also `get_modifier_keys`.
"""
struct ModifierKeys
    ctrl::Bool
    shift::Bool
    alt::Bool
    meta::Bool
end

ModifierKeys(; ctrl::Bool=false, shift::Bool=false, alt::Bool=false, meta::Bool=false) =
    ModifierKeys(ctrl, shift, alt, meta)
