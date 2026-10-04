"""
    GestureHelpModule

The gesture help domain: the gesture map, the command palette, the projections
that draw them, and the two decorators that put them on screen. This file holds
the map, which the rest of the slice is written in terms of.

A `GestureMap` is a read-only document listing the gesture bindings available in some context — the
rendered face of the reified `GestureBinding` data. Each [`GestureRow`](@ref)
pairs a gesture rendering (`describe_gesture_pattern(pattern)`) with what it does and whether it
is currently applicable; [`GestureMapToSyntax`](@ref)
projects a `GestureMap` onto the existing Syntax → Text → Graphics pipeline so the
help window reuses the normal display path.

Build one from a collection of intents (applicability is evaluated against the
document's current selection at the time they were collected):

    make_gesture_map(read_intent(pipeline, recursion, Intent(CollectIntents()), iomap).operation)
"""
module GestureHelpModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EventModule
using ..EventModule
using ..GestureBindingModule
using ..GestureModule
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
using ..EditorModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..EditorModule: wrap_editor!, get_wrapper_layers

export GestureRow, make_gesture_row, make_gesture_map, collect_gesture_rows
export CommandPalette, build_command_palette_selection, get_command_palette_selected,
       get_command_palette_matches, get_command_palette_row, compute_command_palette_step,
       get_command_palette_settled_selection
export GestureHelpTheme, ScaledGestureHelpTheme
export GestureMapToSyntax, make_gesture_map_syntax_projection
export CommandPaletteToSyntax, make_command_palette_syntax_projection
export CommandPaletteDecoratorProjection, CommandPaletteState, CommandPaletteDecoratorIoMap,
       COMMAND_PALETTE_GESTURE, is_command_palette_gesture,
       make_command_palette_projection, ToggleCommandPaletteOperation
export GestureHelpDecoratorProjection, GestureHelpState, GestureHelpDecoratorIoMap,
       HELP_GESTURE, is_help_gesture, make_gesture_map_projection, ToggleGestureHelpOperation
export GestureMap


include("GestureMap.jl")
include("CommandPalette.jl")
include("GestureHelpTheme.jl")
include("GestureMapToSyntax.jl")
include("CommandPaletteToSyntax.jl")
include("CommandPaletteDecorator.jl")
include("GestureHelpDecorator.jl")

end # module
