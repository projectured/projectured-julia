"""
    NavigatorModule

The navigator: a document that shows one part of another document, its page, as
a tab of a browser shows one page of a site. `Navigator` holds the content, which
can be a document of any domain, the address of the page in it, and the visits
before and after the current one. Back, Forward and Parent move between pages,
and an open of a part makes it the page. `NavigatorToWidget` draws a bar of
buttons and the address above the page, and the renderer draws the page with the
row of its own type, so the navigator knows nothing of the domain of the page. A
link answers `OpenPageOperation`: the nearest navigator around it opens the page,
and an open that no navigator takes opens a tab with a navigator of its own.
"""
module NavigatorModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EventModule
using ..FileSystemModule
using ..GestureBindingModule
using ..GestureModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PaneModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..ScreenModule
using ..SelectionModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title, get_edited_field, has_document_duplicate, is_walk_opaque
import ..PaneModule: make_pane_tab_title
import ..SerializationModule: pred_arguments, make_pred_document
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..OperationModule: evaluate_operation

export NavigatorVisit, ReferenceInsertion, NavigatorAddress, NavigatorChoiceList, Navigator
export get_navigator_page_address, get_navigator_address_steps, get_navigator_page,
       find_navigator_parent_address, is_navigator_stop, find_navigator_selected_address,
       make_navigator_open_operation, make_navigator_back_operation,
       make_navigator_forward_operation, make_navigator_parent_operation
export find_navigator_choices, make_navigator_choice_operation
export make_navigator_address_edit_operation, make_navigator_address_commit_operation,
       make_navigator_address_reset_operation, is_navigator_address_selected
export OpenPageOperation, find_navigator_target
export make_navigator_address_projection, ReferenceStepToSyntaxLeaf
export NavigatorToWidget, make_navigator_projection
export NavigatorChoiceListToWidget, make_navigator_choice_list_projection

include("NavigatorDocument.jl")
include("NavigatorVisits.jl")
include("NavigatorChoices.jl")
include("NavigatorAddressEdits.jl")
include("NavigatorGestures.jl")
include("OpenPageOperation.jl")
include("NavigatorAddressToSyntax.jl")
include("NavigatorToWidget.jl")
include("NavigatorChoiceListToWidget.jl")

# The row that lets a tab draw a navigator. The factory form, so every renderer
# builds its own projection instance. The bar and the page come back through the
# recursion of the renderer, which draws the page with the row of its own type.
function __init__()
    register_natural_graphics!(:navigator, (; measure, appearance) -> Pair{Type,Any}[
        Navigator => ChainingProjection(
            make_navigator_projection(; widget_theme = get_scaled_theme!(appearance, WidgetTheme),
                                      syntax_theme = get_scaled_theme!(appearance, SyntaxTheme)),
            GridLayoutToGraphicsCanvas()),
        NavigatorChoiceList => ChainingProjection(
            make_navigator_choice_list_projection(; widget_theme = get_scaled_theme!(appearance, WidgetTheme)),
            GridLayoutToGraphicsCanvas())])
end

end # module
