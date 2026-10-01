# Fragment of `AppearanceModule` — the operations that step the zoom and the
# scales of an appearance.

"""
    APPEARANCE_SCALES

The six scales of an `Appearance` that `AdjustScaleOperation` steps.
"""
const APPEARANCE_SCALES = (:font_scale, :icon_scale, :spacing_scale,
                           :control_scale, :radius_scale, :line_scale)

"""
    AdjustZoomOperation(appearance, delta)

Step the zoom of `appearance` by `delta` in the table of `step_factor`: `+1`
zooms in, `-1` zooms out, and `0` gives `1.0`. The evaluation also copies the
zoom into the `Display` of the editor, where the backends read it.
"""
struct AdjustZoomOperation <: Operation
    appearance::Appearance
    delta::Int
end

"""
    AdjustScaleOperation(appearance, scale, delta)

Step the scale `scale` of `appearance`, one of [`APPEARANCE_SCALES`](@ref), by
`delta`, as `AdjustZoomOperation` steps the zoom.
"""
struct AdjustScaleOperation <: Operation
    appearance::Appearance
    scale::Symbol
    delta::Int
    function AdjustScaleOperation(appearance::Appearance, scale::Symbol, delta::Integer)
        scale in APPEARANCE_SCALES ||
            throw(ArgumentError("$(repr(scale)) is not a scale of an appearance; " *
                                "the scales are $(APPEARANCE_SCALES)"))
        new(appearance, scale, Int(delta))
    end
end

function evaluate_operation(editor, operation::AdjustZoomOperation)
    appearance = operation.appearance
    appearance.zoom = step_factor(appearance.zoom, operation.delta)
    copy_zoom_to_display!(editor, appearance)
    nothing
end

function evaluate_operation(editor, operation::AdjustScaleOperation)
    appearance = operation.appearance
    setproperty!(appearance, operation.scale,
                 step_factor(getproperty(appearance, operation.scale), operation.delta))
    nothing
end

"""
    copy_zoom_to_display!(editor, appearance) -> nothing

Copy the zoom of `appearance` into the `Display` of `editor`, where a backend
reads it. A missing editor, or one with no `Display`, gets nothing.
"""
function copy_zoom_to_display!(editor, appearance::Appearance)
    editor === nothing && return nothing
    for device in editor.devices
        device isa Display && (device.zoom = appearance.zoom)
    end
    nothing
end

# The direction of a step, for the description of an operation.
_describe_step(delta::Integer) = delta > 0 ? "larger" : delta < 0 ? "smaller" : "reset"

describe_operation(operation::AdjustZoomOperation) =
    "zoom " * (operation.delta > 0 ? "in" : operation.delta < 0 ? "out" : "reset")
describe_operation(operation::AdjustScaleOperation) =
    replace(String(operation.scale), "_" => " ") * " " * _describe_step(operation.delta)

# A step of the zoom or of a scale is no edit of the content, so the history
# takes nothing back for it.
make_inverse_operation(document, ::Union{AdjustZoomOperation, AdjustScaleOperation}) =
    DoNothingOperation()

# Each carries the appearance that it writes, so it travels up a chain as it is.
operation_travels_unchanged(::Union{AdjustZoomOperation, AdjustScaleOperation}) = true
