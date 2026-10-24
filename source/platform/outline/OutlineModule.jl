"""
    OutlineModule

The kit of an outline of records, such as a study or a workflow: one theme, and
the builders of the parts that a row of a record shows. A row has a column of its
facts (its fold, its mark, its id, its author and its time), the column of its
text, and a column for its menu. A domain builds its view from these parts, so a
study and a workflow read as one notation.
"""
module OutlineModule

using ..AgentModule
using ..CellModule
using ..DocumentModule
using ..DomainModule
using ..EditorModule
using ..GestureBindingModule
using ..GestureModule
using ..LayoutModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..StyleModule
using ..ToolModule
using ..TooltipModule
using ..WidgetModule

export OutlineTheme, ScaledOutlineTheme
export compute_shown_dates
export OutlineSlot, map_outline_forward, map_outline_backward, route_outline_paths!
export make_outline_label, make_outline_text, make_outline_chip, make_outline_mark, make_outline_control,
       make_outline_spacer, make_outline_avatar, make_outline_facts, make_outline_field, make_outline_relations,
       make_outline_section, make_outline_menu_operation, make_outline_row, make_outline_card,
       make_outline_guides, get_outline_guide_steps
export make_add_element_operation, make_remove_element_operation, make_new_element_operation,
       make_element_cancel_operation, make_move_element_operation, make_element_choice_list,
       make_outline_element, get_outline_element_steps, make_element_menu, add_element!

include("OutlineTheme.jl")
include("OutlineDate.jl")
include("OutlinePaths.jl")
include("OutlineRow.jl")
include("OutlineElements.jl")

end # module
