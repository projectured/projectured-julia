"""
    InspectorModule

`ReferenceInspector` — pairs a `reference` (`Reference` or `nothing`) with
the `target` document it points into. `ReferenceInspectorToText` renders both
forms (compact + human narrative).
"""
module InspectorModule

using ..CellModule
using ..DocumentModule
using ..DomainModule
using ..IoMapModule
using ..NaturalModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..SerializationModule
using ..StyleModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: get_insertion_aliases
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward
import ..SerializationModule: pred_arguments

export InspectorTheme, ScaledInspectorTheme
export ReferenceInspectorToText, make_reference_inspector_projection
export ReferenceInspector
export SelectionInspector, SelectionInspectorToText,
       find_inspected_selection, get_inspected_document


include("ReferenceInspector.jl")
include("SelectionInspector.jl")
include("InspectorTheme.jl")
include("ReferenceInspectorToText.jl")
include("SelectionInspectorToText.jl")

# ── Natural-projection registration ─────────────────────────────────────────
#
# The rows that let a tab draw an inspector. A module takes one `__init__`, and
# this module owns two projections, so both rows are registered here rather than
# beside each projection.
#
# The factory form, so every renderer builds its own projection instances.

function __init__()
    register_natural_graphics!(:inspector, (; measure, appearance) -> begin
        theme = get_scaled_theme!(appearance, InspectorTheme)
        reference_theme = get_scaled_theme!(appearance, ReferenceTheme)
        text = TextToGraphics(; measure, theme = get_scaled_theme!(appearance, TextTheme))
        Pair{Type,Any}[
            ReferenceInspector => ChainingProjection(make_reference_inspector_projection(; theme, reference_theme),
                                                     WordWrapping(measure = measure),
                                                     text),
            SelectionInspector => ChainingProjection(SelectionInspectorToText(; theme, reference_theme),
                                                     WordWrapping(measure = measure),
                                                     text),
        ]
    end)
end

end # module
