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

"""
    ReplaceThemeValueOperation(write)

`write`, a `ReplaceReferencedValueOperation` of one field of a theme, and then a
new print of the view, so that every projection reads the new value. The
projections read their themes with no edge, so the write alone changes no view.

The inverse writes the old value and prints the view again. So a history that
records a change of a theme takes it back, and the view shows the old value. The
`appearance` wrapper makes this operation from each write of a theme of its
appearance; any other path can post it as it is.
"""
struct ReplaceThemeValueOperation <: WrappingOperation
    operation::ReplaceReferencedValueOperation
    function ReplaceThemeValueOperation(operation::ReplaceReferencedValueOperation)
        operation.document isa Theme ||
            throw(ArgumentError("ReplaceThemeValueOperation writes into a theme, " *
                                "not into $(typeof(operation.document))"))
        new(operation)
    end
end

get_wrapped_operation(operation::ReplaceThemeValueOperation) = operation.operation
rewrap_operation(::ReplaceThemeValueOperation, inner) = ReplaceThemeValueOperation(inner)

function evaluate_operation(editor, operation::ReplaceThemeValueOperation)
    evaluate_operation(editor, operation.operation)
    editor === nothing || evaluate_operation(editor, InvalidateProjectionOperation())
    nothing
end

function make_inverse_operation(document, operation::ReplaceThemeValueOperation)
    inverse = make_inverse_operation(document, operation.operation)
    inverse isa ReplaceReferencedValueOperation ? ReplaceThemeValueOperation(inverse) : inverse
end

function describe_operation(operation::ReplaceThemeValueOperation)
    write = operation.operation
    head = get_reference_head(strip_reference_types(write.reference))
    field = head isa AFieldReferenceStep ? replace(head.name, "_" => " ") : "a value"
    "set " * field * " of " * string(nameof(get_theme_type(write.document)))
end

# It carries the theme that it writes, so it travels up a chain as it is.
operation_travels_unchanged(::ReplaceThemeValueOperation) = true

"""
    SaveAppearanceOperation(appearance, path = get_appearance_file())

Write `appearance` into the file `path` with `save_appearance!`. The view does not
change.
"""
struct SaveAppearanceOperation <: Operation
    appearance::Appearance
    path::String
end

SaveAppearanceOperation(appearance::Appearance) = SaveAppearanceOperation(appearance, get_appearance_file())

"""
    LoadAppearanceOperation(appearance, path = get_appearance_file())

Read the file `path` into `appearance` with `load_appearance!`, and copy its zoom
into the `Display` of the editor. It changes the appearance, so the view prints
again.
"""
struct LoadAppearanceOperation <: Operation
    appearance::Appearance
    path::String
end

LoadAppearanceOperation(appearance::Appearance) = LoadAppearanceOperation(appearance, get_appearance_file())

evaluate_operation(editor, operation::SaveAppearanceOperation) =
    (save_appearance!(operation.appearance, operation.path); nothing)

function evaluate_operation(editor, operation::LoadAppearanceOperation)
    load_appearance!(operation.appearance, operation.path)
    copy_zoom_to_display!(editor, operation.appearance)
    nothing
end

describe_operation(operation::SaveAppearanceOperation) = "save the appearance"
describe_operation(operation::LoadAppearanceOperation) = "load the appearance"

make_inverse_operation(document, ::Union{SaveAppearanceOperation, LoadAppearanceOperation}) =
    DoNothingOperation()

operation_travels_unchanged(::Union{SaveAppearanceOperation, LoadAppearanceOperation}) = true
