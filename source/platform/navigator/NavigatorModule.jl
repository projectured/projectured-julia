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
using ..GestureBindingModule
using ..GestureModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PaneModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title, get_edited_field
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..OperationModule: evaluate_operation

export Navigator, NavigatorVisit
export get_navigator_page_address, get_navigator_page, find_navigator_parent_address,
       find_navigator_selected_address
export make_navigator_open_operation, make_navigator_back_operation,
       make_navigator_forward_operation, make_navigator_parent_operation
export NavigatorToWidget, make_navigator_projection
export OpenPageOperation

include("NavigatorDocument.jl")
include("NavigatorVisits.jl")
include("NavigatorGestures.jl")
include("OpenPageOperation.jl")
include("NavigatorToWidget.jl")

# The row that lets a tab draw a navigator. The factory form, so every renderer
# builds its own projection instance. The bar and the page come back through the
# recursion of the renderer, which draws the page with the row of its own type.
function __init__()
    register_natural_graphics!(:navigator, (; measure, appearance) -> Pair{Type,Any}[
        Navigator => ChainingProjection(
            make_navigator_projection(; widget_theme = get_scaled_theme!(appearance, WidgetTheme)),
            GridLayoutToGraphicsCanvas())])
end

end # module
