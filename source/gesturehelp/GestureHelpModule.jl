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
using ..CollectionModule
using ..DocumentModule
using ..EventModule
using ..EventModule
using ..GestureBindingModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..ScreenModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export GestureRow, make_gesture_row, make_gesture_map, collect_gesture_rows
export CommandPalette, build_command_palette_selection, get_command_palette_selected,
       get_command_palette_matches, get_command_palette_row, compute_command_palette_step,
       get_command_palette_settled_selection
export GestureMapToSyntax
export CommandPaletteToSyntax
export CommandPaletteDecoratorProjection, CommandPaletteState, CommandPaletteDecoratorIoMap,
       COMMAND_PALETTE_GESTURE, PALETTE_PADDING, is_command_palette_gesture,
       make_command_palette_projection
export GestureHelpDecoratorProjection, GestureHelpState, GestureHelpDecoratorIoMap,
       HELP_GESTURE, is_help_gesture, make_gesture_map_projection
export GestureMap


include("GestureMap.jl")
include("CommandPalette.jl")
include("GestureMapToSyntax.jl")
include("CommandPaletteToSyntax.jl")
include("CommandPaletteDecorator.jl")
include("GestureHelpDecorator.jl")

end # module
