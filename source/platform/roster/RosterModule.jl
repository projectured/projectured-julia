"""
    RosterModule

A list of all the members of one kind, gathered from anywhere in a session: the
`Roster`, its rows, the sources that give its items, the facets that name the
values of an item, and the projection that shows a roster as a table. A filter, a
sort and the other steps of an arrangement act on the rows of a roster as on any
collection. Each slice that owns a kind of item or a store adds its own source
and its own facets, so this module names none of them.
"""
module RosterModule

using ..ArrangementModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EditorModule
using ..FocusModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..ScreenModule
using ..SerializationModule
using ..StyleModule
using ..ToolModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..ArrangementModule: find_arrangement_key_value, get_arrangement_value, get_arranged_collection_steps
import ..DocumentModule: get_document_title, is_walk_opaque
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward,
                           get_child_iomaps
import ..SerializationModule: pred_arguments, make_pred_document, is_pred_constructible

export collect_roster_parts, collect_roster_items, get_roster_item_type, get_item_facets, compute_item_facet,
       make_item_facet_operation
export RosterItem, RosterRow, make_roster_row, compute_roster_value, collect_item_facets, format_roster_value,
       Roster, link_roster!
export CollectionItems, ItemsWithin, register_roster_source!, get_roster_source_names, StoreRecords
export RosterToGraphics, RosterToGraphicsIoMap, RosterRowsToWidget, RosterRowsToWidgetIoMap
export show_roster!, describe_roster, describe_roster_sources, describe_item_facets, edit_shown_items!

include("RosterInterface.jl")
include("RosterDefaults.jl")
include("RosterDocument.jl")
include("RosterSource.jl")
include("RosterToGraphics.jl")
include("RosterProgram.jl")

function __init__()
    register_natural_graphics!(:roster, _make_roster_graphics_entries)
end

end # module
