# Fragment of `GestureTrackingModule` — the settings of the recognitions of the
# pointer.

"""
    PointerSettings(; multi_click_max_interval = 0.3, click_max_displacement = 5,
                      dwell_delay = 0.5)

The limits of the recognitions of the pointer: the time of a double click, the
distance that a click can move, and the rest of the pointer before a dwell, which
opens a tooltip. [`make_standard_recognitions`](@ref)`(settings)` gives the
recognitions the cells of the group, so a change reaches them at the next input.
"""
@settings struct PointerSettings
    "Double click time: the most seconds between the clicks of a double click."
    multi_click_max_interval::Float64 = 0.3 in 0.1:0.05:1.0
    "Click distance: the most pixels that a press can move and still be a click."
    click_max_displacement::Int = 5 in 1:20
    "Tooltip delay: the seconds that the pointer rests before a tooltip opens."
    dwell_delay::Float64 = 0.5 in 0.1:0.1:3.0
end

"""
    make_standard_recognitions(settings::PointerSettings) -> Vector{GestureRecognition}

The standard recognitions, whose limits are the cells of `settings`. The click
distance limits a click and the next click of a double click.
"""
function make_standard_recognitions(settings::PointerSettings)
    displacement = get_setting_cell(settings, :click_max_displacement)
    GestureRecognition[
        ChordRecognition(),
        ClickRecognition(; click_max_displacement = displacement,
                           multi_click_max_displacement = displacement,
                           multi_click_max_interval =
                               get_setting_cell(settings, :multi_click_max_interval)),
        DwellRecognition(; delay = get_setting_cell(settings, :dwell_delay))]
end
