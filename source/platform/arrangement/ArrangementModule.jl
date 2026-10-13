"""
    ArrangementModule

What a person arranges in how a document shows, apart from the document: the
`ArrangementDocument` that holds a document and the projections that a person
placed at its parts, such as a filter or a sort of a collection, the projection
that prints it, the dispatch that puts those projections at their places in a
recursion, the filter and the sort, the bar that shows the chips of a place,
find, and the verbs that filter and sort a collection from code.
"""
module ArrangementModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EditorModule
using ..EventModule
using ..GestureBindingModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionModule
using ..ProjectionAlgebraModule
using ..ReferenceModule
using ..SelectionModule
using ..ToolModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title, get_wrapped_document, get_edited_field, replace_wrapped_document!
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward,
                           get_child_iomaps
import ..OperationModule: operation_reference, retarget_operation

export ArrangementDocument, ArrangementEntry, ArrangementChips, ArrangementFilter, ArrangementCondition,
       is_quick_text_condition, ArrangementSort, ArrangementSortKey, ArrangementFind
export ArrangeCollectionOperation, make_arrangement_change_edit, make_first_arrangement, make_entry_removal_edit
export make_arrangement_projection, ArrangingProjection, ArrangingIoMap, make_arranged_dispatch,
       find_arranged_projection, ArrangedChainingProjection, get_arranged_wrap_steps
export PickingProjection, PickingIoMap, get_arrangement_value, find_arrangement_key_value, compute_filter_rows,
       is_condition_holding, compute_sort_rows, compare_arrangement_values
export ArrangementBarProjection, ArrangementBarIoMap
export compute_shown_rows, make_field_caret_reference, find_arranged_place, is_in_find_field,
       make_find_field_selection, make_first_find, make_find_move
export get_arrangement_parts, describe_arrangement_part, describe_arranged_collection, describe_arrangement,
       filter_collection!,
       sort_collection!, make_filter_collection_operation, make_sort_collection_operation
export find_arranged_item, make_arrangement_edits, make_first_arrangement_edits

include("ArrangementDocument.jl")
include("ArrangeCollectionOperation.jl")
include("Arranging.jl")
include("Picking.jl")
include("ArrangementBar.jl")
include("Finding.jl")
include("ArrangementProgram.jl")
include("ArrangementMenu.jl")

end # module
