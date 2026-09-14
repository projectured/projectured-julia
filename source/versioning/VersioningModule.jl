"""
    VersioningModule

Object-versioning as a domain-neutral overlay: any document subtree can carry
multiple versions. `VersionedObject` holds the list; `ObjectVersion` pairs a
value with `VersionProperties` (when/who/where). Elimination happens through
`VersioningToAnyProjection`, which picks one version by criterion.
"""
module VersioningModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventPatternModule
using ..GestureBindingModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule

# Imported to extend: this module adds a method to each of these.
import ..OperationModule: evaluate_operation
import ..ProjectionModule: get_projection_gesture_bindings
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export VersioningDocument, VersionCriterion, VersionCriterionLatest, VersionCriterionIndex,
       VersionCriterionByAuthor, VersionCriterionAsOf, VersionCriterionPredicate, select_version
export VersioningToAnyProjection, VersioningToAnyIoMap,
       SetVersionCriterionOperation
export VersionedObject, ObjectVersion


include("VersioningDocument.jl")
include("VersioningToAny.jl")

end # module
