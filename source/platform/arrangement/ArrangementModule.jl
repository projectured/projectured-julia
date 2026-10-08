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
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export ArrangementDocument, ArrangementEntry
export ArrangementFilter, ArrangementCondition, ArrangementSort, ArrangementSortKey
export ArrangingProjection, ArrangingIoMap, ArrangedChainingProjection
export PickingProjection, PickingIoMap
export make_arrangement_projection, make_arranged_dispatch, find_arranged_projection
export get_arrangement_value, compute_filter_rows, compute_sort_rows, is_condition_holding,
       compare_arrangement_values

include("ArrangementDocument.jl")
include("Arranging.jl")
include("Picking.jl")

end # module
