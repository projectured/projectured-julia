"""
    GestureHelpModule

The gesture help domain: the gesture map, the command palette, the projections
that draw them, and the two decorators that put them on screen. This file holds
the map, which the rest of the slice is written in terms of.

A `GestureMap` is a read-only document listing the gesture bindings available in some context — the
rendered face of the reified `GestureBinding` data. Each [`GestureRow`](@ref)
pairs a gesture rendering (`describe_event_pattern(pattern)`) with what it does and whether it
is currently applicable; [`GestureMapToSyntax`](../projection/primitive/GestureMapToSyntax.jl)
projects a `GestureMap` onto the existing Syntax → Text → Graphics pipeline so the
help window reuses the normal display path.

Build one from a binding list and the document the bindings act on (applicability
is evaluated against that document's current selection):

    make_gesture_map(read_intent(pipeline, recursion, Intent(CollectIntents()), iomap).operation)
    make_gesture_map(get_document_gesture_bindings(JsonObject), some_object)   # global, by type
"""
module GestureHelpModule

using ..CellModule
using ..DocumentModule
using ..ReferenceModule
using ..GestureBindingModule
using ..IntentModule
using ..EventPatternModule
export GestureRow, make_gesture_row, make_gesture_map, collect_gesture_rows
export CommandPalette, build_command_palette_selection, get_command_palette_selected,
       get_command_palette_matches, get_command_palette_row, compute_command_palette_step,
       get_command_palette_settled_selection
using ..ProjectionApiModule
import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..ProjectionModule
using ..IoMapModule
using ..TextModule
using ..StyleModule
using ..SyntaxModule
using ..PrinterContextModule
export GestureMapToSyntax
export CommandPaletteToSyntax
using ..CollectionModule
using ..OperationModule
using ..EventModule
using ..ProjectionAlgebraModule
using ..WordWrappingModule
using ..TextToGraphicsModule
using ..GraphicsModule
export CommandPaletteDecoratorProjection, CommandPaletteState, CommandPaletteDecoratorIoMap,
       COMMAND_PALETTE_GESTURE, PALETTE_PADDING, is_command_palette_gesture,
       make_command_palette_projection
using ..ScreenModule
export GestureHelpDecoratorProjection, GestureHelpState, GestureHelpDecoratorIoMap,
       HELP_GESTURE, is_help_gesture
export GestureMap




"""
    GestureRow(gesture, description, domain, operation)

One display row: `gesture` is the keystroke/click rendering
(`describe_event_pattern` of the pattern, and the empty string for a binding that
has no gesture), `description` is what it does, and `domain` groups rows under a
heading.

`operation` is the change this row would make, **already built and already rooted
where the caller can apply it** — because the row came back through the reader,
which is what roots it. `nothing` means the row cannot run right now: its
precondition failed, or it needs a keystroke to carry its argument. That is the
greyed row, and it is the only "can this fire?" answer there is.
"""
struct GestureRow
    gesture::String
    description::String
    domain::String
    operation::Any
end

"""
    GestureMap(rows = GestureRow[])

A document wrapping the gesture rows for display. Read-only: it carries the
`selection` field the `Document` contract requires, but no editing gestures of
its own.
"""
@document struct GestureMap
    rows::Any = GestureRow[]
end

# An intent with no pattern has no keystroke to render, so its gesture column is
# empty. The intent's `gesture` field carries the binding's pattern, which is what
# a listing renders — the input that *would* fire it.
_row_gesture(pattern) = pattern === nothing ? "" : describe_event_pattern(pattern)

"""
    make_gesture_row(intent) -> GestureRow

One row for one collected `Intent`. Nothing is evaluated here: the operation was
built by the binding that owns it, against the document that owns it, and rooted
by every stage on the way back.
"""
make_gesture_row(intent::Intent) =
    GestureRow(_row_gesture(intent.gesture), intent.description, intent.domain,
               intent.operation)

"""
    collect_gesture_rows(collected) -> Vector{GestureRow}

The rows for a [`CollectedIntentsOperation`](@ref), in collection order — which is
chain order, so the innermost document's rules come first. A chain that visits one
document from more than one stage offers it more than once; the same
(domain, description) is kept only the first time.

`nothing` (a reader that had nothing to say) yields no rows.
"""
function collect_gesture_rows(collected::CollectedIntentsOperation)
    rows = GestureRow[]
    seen = Set{Tuple{String,String}}()
    for intent in collected.intents
        key = (intent.domain, intent.description)
        key in seen && continue
        push!(seen, key)
        push!(rows, make_gesture_row(intent))
    end
    rows
end
collect_gesture_rows(::Nothing) = GestureRow[]
collect_gesture_rows(::Any) = GestureRow[]

"""
    make_gesture_map(collected) -> GestureMap

The help window's document for a collection.
"""
make_gesture_map(collected) = GestureMap(collect_gesture_rows(collected), nothing)


include("CommandPalette.jl")
include("GestureMapToSyntax.jl")
include("CommandPaletteToSyntax.jl")
include("CommandPaletteDecorator.jl")
include("GestureHelpDecorator.jl")

end # module
