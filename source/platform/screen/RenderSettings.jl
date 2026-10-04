# Fragment of `ScreenModule` — the settings of the repaint of the windows.

"""
    RenderSettings(; partial_render = true, debug_dirty = false,
                     debug_dirty_hold = 0.0, supersample = 2)

How the editor repaints its windows: only the parts that changed, an outline
of what it repaints, and how smooth the edges look.

How a backend repaints the windows of the screen. A backend that draws windows
applies the group with a method of `apply_settings!`; a backend with no method
ignores it.

`PROJECTURED_PARTIAL_RENDER`, `PROJECTURED_DEBUG_DIRTY` and
`PROJECTURED_SUPERSAMPLE` set the settings of the same names for one run.
"""
@settings struct RenderSettings
    "Partial render: repaint only the parts of a window that changed."
    partial_render::Bool = true
    "Repaint outline: outline in red the parts of a window that a frame repaints."
    debug_dirty::Bool = false
    "Outline hold: keep each outline for this number of seconds."
    debug_dirty_hold::Float64 = 0.0 in 0.0:0.5:5.0
    "Supersample: pixels in each direction for each pixel of a window; 1 turns it off."
    supersample::Int = 2 in 1:4
end

is_settings_group_applied(::Type{RenderSettings}) = true

get_setting_environment_names(::Type{RenderSettings}) =
    (partial_render = "PROJECTURED_PARTIAL_RENDER",
     debug_dirty = "PROJECTURED_DEBUG_DIRTY",
     supersample = "PROJECTURED_SUPERSAMPLE")
