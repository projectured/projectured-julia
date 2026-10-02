"""
    FocusModule

Focus traversal — the generic walk that finds the first / last focusable leaf
in a document subtree, and the selection that a left button down on a focusable
leaf makes.

Focus is selection. These pure helpers locate the *first* / *last* focusable
leaf as a relative whole-element (∅) path, mirroring the generic field/element
descent the selection machinery uses, so the produced path matches the
projection readers' re-rooting (`elements[i]` / `children[i]`, with
`RangeReferenceStep(i-1, i)` for the i-th element).

The walk names no widget type. `is_focusable_document` is the open trait a
document domain adds a method to: `WidgetModule` marks its enabled interactive
leaves as the Tab stops. Both `LayoutToGraphics` and `WidgetToGraphics` share
the walk for Tab traversal.

The module also holds the whole-element selection that an Alt+click makes: the
gesture test, the test that tells a whole selection from a caret, and the answer
a container gives for the child a press hit, and the walk of such a selection
with the four Alt + arrow keys (`SelectionWalkingProjection`). Tab starts over
at the ends of a document in `FocusCyclingProjection`. A selection can also name
a widget that a projection drew for a document (`OutputReferenceStep`).
"""
module FocusModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EventModule
using ..GestureModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..EditorModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..ReferenceModule: get_reference_step_kind, evaluate_reference_step
import ..EditorModule: wrap_editor!, get_wrapper_layers, is_wrapper_default

export get_first_focusable_path, get_last_focusable_path, get_next_focusable_index,
       is_focusable_document, is_focusing_press, convert_to_focus_selection
export is_whole_selection_press, is_whole_selection, convert_to_whole_selection,
       find_whole_selected_index, is_whole_selected_field
export FocusCyclingProjection, FocusCyclingIoMap
export SelectionWalkingProjection, SelectionWalkingIoMap,
       get_selection_walk_direction, compute_selection_walk, is_selection_walk_stop
export OutputReferenceStep, make_output_reference, find_output_path,
       follow_output_selection!, follow_output_mouse_target!,
       find_output_node_path, map_held_node_forward, map_held_node_backward


include("Focus.jl")
include("WholeSelection.jl")
include("SelectionWalking.jl")
include("FocusCycling.jl")
include("OutputSelection.jl")

end # module
