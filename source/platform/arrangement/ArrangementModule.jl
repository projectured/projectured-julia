"""
    ArrangementModule

What a person arranges in how a document shows, apart from the document: the
`ArrangementDocument` that holds a document and the projections that a person
placed at its parts, such as a filter or a sort of a collection, the projection
that prints it, and the dispatch that puts those projections at their places in
a recursion.
"""
module ArrangementModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ProjectionAlgebraModule
using ..ReferenceModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export ArrangementDocument, ArrangementEntry
export ArrangingProjection, ArrangingIoMap
export make_arrangement_projection, make_arranged_dispatch, find_arranged_projection

include("ArrangementDocument.jl")
include("Arranging.jl")

end # module
