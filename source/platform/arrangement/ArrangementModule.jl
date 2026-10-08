"""
    ArrangementModule

What a person arranges in how a document shows, apart from the document: the
`ArrangementDocument` that holds a document and the projections that a person
placed at its parts, such as a filter or a sort of a collection, the projection
that prints it, the dispatch that puts those projections at their places in a
recursion, and the filter and the sort.
"""
module ArrangementModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionModule
using ..ProjectionAlgebraModule
using ..ReferenceModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward,
                           get_child_iomaps
import ..OperationModule: operation_reference, retarget_operation

export ArrangementDocument, ArrangementEntry, ArrangementChips, ArrangementFilter, ArrangementCondition,
       ArrangementSort, ArrangementSortKey
export ArrangeCollectionOperation, make_arrangement_change_edit, make_first_arrangement, make_entry_removal_edit
export make_arrangement_projection, ArrangingProjection, ArrangingIoMap, make_arranged_dispatch,
       find_arranged_projection, ArrangedChainingProjection, get_arranged_wrap_steps
export PickingProjection, PickingIoMap, get_arrangement_value, compute_filter_rows, is_condition_holding,
       compute_sort_rows, compare_arrangement_values
export find_arranged_item, make_arrangement_edits, make_first_arrangement_edits

include("ArrangementDocument.jl")
include("ArrangeCollectionOperation.jl")
include("Arranging.jl")
include("Picking.jl")
include("ArrangementMenu.jl")

end # module
